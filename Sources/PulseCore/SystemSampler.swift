import Foundation
import Darwin
import IOKit
import SystemConfiguration

/// Confined to the sampling queue. No subprocesses, elevated privileges or retained registry objects.
public final class SystemSampler {
    private let host = mach_host_self()
    private var lastCPU: CPUCounters?
    private var network = NetworkDiffer()
    public init() {}
    deinit { mach_port_deallocate(mach_task_self_, host) }

    public func reset() {
        lastCPU = nil; network.reset()
    }
    public func sample() -> Snapshot {
        let uptime = ProcessInfo.processInfo.systemUptime
        let counters = readCPU()
        let cpu = counters.flatMap { current in lastCPU.flatMap { current.utilization(since: $0) } }
        lastCPU = counters
        return Snapshot(cpu: cpu, gpu: readGPU(), memory: readMemory(),
                        network: network.update(readInterfaces(), at: uptime))
    }
    private func readCPU() -> CPUCounters? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUCounters(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }
    private func readMemory() -> MemoryReading? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        var page: vm_size_t = 0
        guard host_page_size(host, &page) == KERN_SUCCESS else { return nil }
        let app = Double(info.internal_page_count) - min(Double(info.internal_page_count), Double(info.purgeable_count))
        let compressed = Double(info.compressor_page_count) * Double(page)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return MemoryReading(used: min(total, (app + Double(info.wire_count)) * Double(page) + compressed), total: total, compressed: compressed)
    }
    private func readGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var values: [Double] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let stats = property as? [String: Any],
                  let number = stats["Device Utilization %"] as? NSNumber else { continue }
            let value = number.doubleValue
            if value.isFinite && (0...100).contains(value) { values.append(value) }
        }
        return values.max()
    }
    private func readInterfaces() -> [String: InterfaceCounters]? {
        // NET_RT_IFLIST2 provides 64-bit counters, unlike getifaddrs' 32-bit if_data.
        guard let links = SCDynamicStoreCopyMultiple(nil, nil, ["State:/Network/Interface/.*/Link"] as CFArray) as? [String: [String: Any]] else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<if_msghdr2>.alignment)
        defer { buffer.deallocate() }
        guard sysctl(&mib, u_int(mib.count), buffer, &size, nil, 0) == 0 else { return nil }
        var offset = 0
        var counters: [String: InterfaceCounters] = [:]
        while offset + 4 <= size {
            let pointer = buffer.advanced(by: offset)
            let length = Int(pointer.loadUnaligned(as: UInt16.self))
            guard length >= 4, offset + length <= size else { return nil }
            defer { offset += length }
            guard pointer.load(fromByteOffset: 3, as: UInt8.self) == RTM_IFINFO2,
                  length >= MemoryLayout<if_msghdr2>.size else { continue }
            let info = pointer.loadUnaligned(as: if_msghdr2.self)
            guard info.ifm_flags & IFF_UP != 0, info.ifm_flags & IFF_RUNNING != 0,
                  info.ifm_flags & IFF_LOOPBACK == 0 else { continue }
            var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
            guard if_indextoname(UInt32(info.ifm_index), &name) != nil else { continue }
            let interface = String(cString: name)
            // Physical Ethernet / Wi-Fi links only. Avoid double-counting VPN, AWDL and bridge traffic.
            guard interface.hasPrefix("en"), links["State:/Network/Interface/\(interface)/Link"]?["Active"] as? Bool == true else { continue }
            counters[interface] = InterfaceCounters(received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes)
        }
        return counters
    }
}

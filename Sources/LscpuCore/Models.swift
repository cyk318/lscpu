import Foundation

public struct CPUCounters: Equatable {
    public let user, system, idle, nice: UInt32
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32 = 0) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
    public func utilization(since old: Self) -> Double? {
        let busy = Double(user &- old.user) + Double(system &- old.system) + Double(nice &- old.nice)
        let total = busy + Double(idle &- old.idle)
        return total > 0 ? busy / total * 100 : nil
    }
}

public struct InterfaceCounters: Equatable {
    public let received, sent: UInt64
    public init(received: UInt64, sent: UInt64) { self.received = received; self.sent = sent }
}

public struct NetworkRate: Equatable {
    public let download, upload: Double
    public let interfaces: [String]
    public var connected: Bool { !interfaces.isEmpty }
    public init(download: Double, upload: Double, interfaces: [String]) {
        self.download = download; self.upload = upload; self.interfaces = interfaces
    }
}

/// Each interface has its own baseline. New, removed and reset interfaces never create spikes.
public struct NetworkDiffer {
    private var previous: [String: InterfaceCounters]?
    private var lastTime: TimeInterval?
    public init() {}
    public mutating func reset() { previous = nil; lastTime = nil }
    public mutating func update(_ counters: [String: InterfaceCounters]?, at time: TimeInterval) -> NetworkRate? {
        guard let counters else { reset(); return nil }
        defer { previous = counters; lastTime = time }
        guard let previous, let lastTime, time > lastTime, time - lastTime < 15 else { return nil }
        var received = 0.0, sent = 0.0
        for (name, current) in counters {
            guard let old = previous[name] else { continue }
            if current.received >= old.received { received += Double(current.received - old.received) }
            if current.sent >= old.sent { sent += Double(current.sent - old.sent) }
        }
        return NetworkRate(download: received / (time - lastTime), upload: sent / (time - lastTime), interfaces: counters.keys.sorted())
    }
}

public struct MemoryReading {
    public let used, total, compressed: Double
    public var percent: Double { total > 0 ? min(100, max(0, used / total * 100)) : 0 }
    public init(used: Double, total: Double, compressed: Double) {
        self.used = used; self.total = total; self.compressed = compressed
    }
}

public struct Snapshot {
    public let timestamp: Date
    public let cpu, gpu: Double?
    public let memory: MemoryReading?
    public let network: NetworkRate?
    public init(timestamp: Date = Date(), cpu: Double?, gpu: Double?, memory: MemoryReading?, network: NetworkRate?) {
        self.timestamp = timestamp; self.cpu = cpu; self.gpu = gpu; self.memory = memory
        self.network = network
    }
    public static let empty = Snapshot(cpu: nil, gpu: nil, memory: nil, network: nil)
}

public struct History {
    public private(set) var samples: [Snapshot] = []
    public init() {}
    public mutating func append(_ sample: Snapshot) {
        samples.removeAll { $0.timestamp < sample.timestamp.addingTimeInterval(-60) }
        samples.append(sample)
        // Independent hard cap protects against a misconfigured producer.
        if samples.count > 121 { samples.removeFirst(samples.count - 121) }
    }
    public mutating func reset() { samples.removeAll(keepingCapacity: true) }
}

public enum DisplayFormat {
    public static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))%"
    }
    public static func rate(_ value: Double?) -> String {
        guard let raw = value, raw.isFinite else { return "—" }
        let value = max(0, raw)
        if value >= 1_000_000_000 { return String(format: "%.1f GB/s", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0f KB/s", value / 1_000) }
        return "\(Int(value)) B/s"
    }
    public static func bytes(_ value: Double) -> String { String(format: "%.1f GB", value / 1_073_741_824) }
}

import Foundation
import LscpuCore

final class LscpuCoreChecks {
    func testCPUUsesDeltaAndHandlesCounterWrap() {
        let old = CPUCounters(user: 100, system: 50, idle: 850)
        let current = CPUCounters(user: 120, system: 60, idle: 920)
        expectEqual(current.utilization(since: old)!, 30, accuracy: 0.001)
        expectNil(current.utilization(since: current))
        let wrapped = CPUCounters(user: 4, system: 0, idle: 10)
        expectEqual(wrapped.utilization(since: CPUCounters(user: UInt32.max - 5, system: 0, idle: 0))!, 50, accuracy: 0.001)
    }
    func testNetworkActualElapsedTimeAnd64BitCounters() {
        var differ = NetworkDiffer()
        expectNil(differ.update(["en0": .init(received: 10_000_000_000, sent: 30)], at: 10))
        let rate = differ.update(["en0": .init(received: 10_005_000_000, sent: 250_030)], at: 12.5)!
        expectEqual(rate.download, 2_000_000)
        expectEqual(rate.upload, 100_000)
    }
    func testNetworkSwitchResetDisconnectAndRecovery() {
        var differ = NetworkDiffer()
        _ = differ.update(["en0": .init(received: 500, sent: 600)], at: 1)
        let switched = differ.update(["en1": .init(received: 9_000_000, sent: 9_000_000)], at: 3)!
        expectEqual(switched.download, 0)
        expectEqual(switched.interfaces, ["en1"])
        let reset = differ.update(["en1": .init(received: 10, sent: 20)], at: 5)!
        expectEqual(reset.download, 0)
        expectEqual(reset.upload, 0)
        let offline = differ.update([:], at: 7)!
        expectFalse(offline.connected)
        expectEqual(offline.download, 0)
        expectNil(differ.update(nil, at: 9))
        expectNil(differ.update(["en0": .init(received: 100, sent: 100)], at: 11))
        expectEqual(differ.update(["en0": .init(received: 200, sent: 300)], at: 13)?.upload, 100)
    }
    func testNetworkSleepGapAndMultipleInterfaces() {
        var differ = NetworkDiffer()
        _ = differ.update(["en0": .init(received: 1, sent: 1), "en1": .init(received: 1, sent: 1)], at: 1)
        let result = differ.update(["en0": .init(received: 101, sent: 201), "en1": .init(received: 301, sent: 401)], at: 3)!
        expectEqual(result.download, 200)
        expectEqual(result.upload, 300)
        expectNil(differ.update([:], at: 30))
        differ.reset()
        expectNil(differ.update([:], at: 31))
    }
    func testHistoryIsTimeBasedAndBounded() {
        var history = History()
        for time in stride(from: 0, through: 180, by: 2) {
            history.append(.init(timestamp: Date(timeIntervalSince1970: Double(time)), cpu: 10, gpu: nil, memory: nil, network: nil))
        }
        expectEqual(history.samples.count, 31)
        expectEqual(history.samples.first?.timestamp, Date(timeIntervalSince1970: 120))
        for _ in 0..<1_000 { history.append(history.samples.last!) }
        expectEqual(history.samples.count, 121)
        history.reset()
        expectTrue(history.samples.isEmpty)
    }
    func testUnknownValuesAndHumanReadableRates() {
        expectEqual(DisplayFormat.percent(nil), "—")
        expectEqual(DisplayFormat.rate(nil), "—")
        expectEqual(DisplayFormat.rate(.infinity), "—")
        expectEqual(DisplayFormat.rate(0), "0 B/s")
        expectEqual(DisplayFormat.rate(128_000), "128 KB/s")
        expectEqual(DisplayFormat.rate(2_300_000), "2.3 MB/s")
        expectEqual(DisplayFormat.rate(-1), "0 B/s")
    }
    func testRealSamplerReturnsValidIndependentMetrics() {
        let sampler = SystemSampler()
        let first = sampler.sample()
        expectNil(first.cpu)
        expectNil(first.network)
        expectNotNil(first.memory)
        Thread.sleep(forTimeInterval: 1.1)
        let second = sampler.sample()
        expectNotNil(second.cpu)
        expectNotNil(second.network)
        for value in [second.cpu, second.gpu, second.memory?.percent].compactMap({ $0 }) {
            expectTrue((0...100).contains(value))
        }
        sampler.reset()
        expectNil(sampler.sample().cpu)
    }
}

func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    guard value else { fatalError("Check failed", file: file, line: line) }
}
func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { expectTrue(!value, file: file, line: line) }
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { expectTrue(value == nil, file: file, line: line) }
func expectNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { expectTrue(value != nil, file: file, line: line) }
func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { expectTrue(a == b, file: file, line: line) }
func expectEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) { expectTrue(abs(a - b) <= accuracy, file: file, line: line) }

let checks = LscpuCoreChecks()
let cases: [(String, () -> Void)] = [
    ("CPU delta and overflow", checks.testCPUUsesDeltaAndHandlesCounterWrap),
    ("64-bit counters and elapsed time", checks.testNetworkActualElapsedTimeAnd64BitCounters),
    ("Network switch, reset, disconnect, recovery", checks.testNetworkSwitchResetDisconnectAndRecovery),
    ("Sleep gap and simultaneous interfaces", checks.testNetworkSleepGapAndMultipleInterfaces),
    ("Time-based bounded history", checks.testHistoryIsTimeBasedAndBounded),
    ("Unavailable values and rate formatting", checks.testUnknownValuesAndHumanReadableRates),
    ("Live native API integration", checks.testRealSamplerReturnsValidIndependentMetrics)
]
for (name, run) in cases { run(); print("PASS  \(name)") }
print("All \(cases.count) checks passed.")

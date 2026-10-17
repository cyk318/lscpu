import AppKit
import LscpuCore

if CommandLine.arguments.contains("--diagnose") {
    let sampler = SystemSampler()
    for _ in 0..<4 {
        let sample = sampler.sample()
        let record: [String: Any] = [
            "cpu": sample.cpu as Any? ?? NSNull(), "gpu": sample.gpu as Any? ?? NSNull(),
            "memoryPercent": sample.memory?.percent as Any? ?? NSNull(),
            "downloadBytesPerSecond": sample.network?.download as Any? ?? NSNull(),
            "uploadBytesPerSecond": sample.network?.upload as Any? ?? NSNull(),
            "interfaces": sample.network?.interfaces as Any? ?? NSNull()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), let line = String(data: data, encoding: .utf8) { print(line) }
        Thread.sleep(forTimeInterval: 1)
    }
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}

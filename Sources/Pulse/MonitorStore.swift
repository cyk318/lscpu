import AppKit
import SwiftUI
import PulseCore

func localized(_ english: String, _ chinese: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
}

enum Metric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, network
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return localized("Memory", "内存")
        case .network: return localized("Network", "网络")
        }
    }
    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "square.3.layers.3d"
        case .memory: return "memorychip"
        case .network: return "arrow.up.arrow.down"
        }
    }
    var color: Color {
        switch self {
        case .cpu: return Color(red: 0.33, green: 0.58, blue: 0.86)
        case .gpu: return Color(red: 0.62, green: 0.48, blue: 0.81)
        case .memory: return Color(red: 0.30, green: 0.65, blue: 0.59)
        case .network: return Color(red: 0.34, green: 0.60, blue: 0.76)
        }
    }
}

final class Preferences: ObservableObject {
    @Published var interval: Double { didSet { UserDefaults.standard.set(interval, forKey: "interval") } }
    @Published var visible: Set<String> { didSet { UserDefaults.standard.set(Array(visible), forKey: "visibleMetrics") } }
    init() {
        let saved = UserDefaults.standard.double(forKey: "interval")
        interval = [1.0, 2.0, 3.0].contains(saved) ? saved : 2
        visible = Set(UserDefaults.standard.stringArray(forKey: "visibleMetrics") ?? Metric.allCases.map(\.rawValue)).intersection(Metric.allCases.map(\.rawValue))
    }
    func shows(_ metric: Metric) -> Bool { visible.contains(metric.rawValue) }
    func toggle(_ metric: Metric, enabled: Bool) {
        if enabled { visible.insert(metric.rawValue) } else { visible.remove(metric.rawValue) }
    }
}

/// All sampler state stays on one utility queue. UI receives immutable snapshots on the main queue.
final class SamplingService {
    private let queue = DispatchQueue(label: "app.pulse.sampling", qos: .utility)
    private let sampler = SystemSampler()
    private var timer: DispatchSourceTimer?
    private var generation = 0
    func start(interval: Double, receive: @escaping (Snapshot) -> Void) {
        generation += 1
        let token = generation
        queue.async { [self] in
            timer?.cancel()
            sampler.reset()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(150))
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let snapshot = autoreleasepool { self.sampler.sample() }
                DispatchQueue.main.async { [weak self] in
                    guard self?.generation == token else { return }
                    receive(snapshot)
                }
            }
            timer = source
            source.resume()
        }
    }
    func stop() {
        generation += 1
        queue.async { [self] in timer?.cancel(); timer = nil; sampler.reset() }
    }
}

final class MonitorStore: ObservableObject {
    @Published private(set) var latest = Snapshot.empty
    @Published private(set) var history = History()
    let preferences = Preferences()
    let hardware: String
    var onUpdate: ((Snapshot) -> Void)?
    private let service = SamplingService()
    init() {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: max(1, size))
        hardware = sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0) == 0 ? String(cString: name) : "Mac"
    }
    func start() {
        service.start(interval: preferences.interval) { [weak self] snapshot in
            guard let self else { return }
            history.append(snapshot)
            latest = snapshot
            onUpdate?(snapshot)
        }
    }
    func sleep() { service.stop() }
    func wake() { history.reset(); start() }
}

import SwiftUI
import ServiceManagement
import PulseCore

struct PopoverView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var preferences: Preferences
    var height: CGFloat = 528
    @State private var settings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 34, height: 34).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pulse").font(.system(size: 17, weight: .semibold))
                    Text(store.hardware).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(store.latest.timestamp.timeIntervalSinceNow > -10 ? Metric.memory.color : .secondary).frame(width: 5, height: 5)
                    Text(localized("LIVE", "实时")).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
                }.foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 17)
            Divider().opacity(0.5)
            ScrollView(.vertical) {
                if settings {
                    SettingsView(preferences: preferences)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text(localized("SYSTEM OVERVIEW", "系统概览")).tracking(1.4)
                            Spacer()
                            Text(localized("LAST 60 SECONDS", "最近 60 秒")).tracking(0.7)
                        }.font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                            .padding(.top, 16).padding(.bottom, 7)
                        metricRow(.cpu, current: DisplayFormat.percent(store.latest.cpu),
                                  detail: localized("\(ProcessInfo.processInfo.processorCount) cores · total utilization", "\(ProcessInfo.processInfo.processorCount) 核心 · 总使用率"), value: { $0.cpu })
                        rowDivider
                        metricRow(.gpu, current: DisplayFormat.percent(store.latest.gpu),
                                  detail: store.latest.gpu == nil ? localized("Unavailable on this system", "系统未提供此指标") : localized("Graphics utilization", "图形处理器使用率"), value: { $0.gpu })
                        rowDivider
                        metricRow(.memory, current: DisplayFormat.percent(store.latest.memory?.percent),
                                  detail: store.latest.memory.map { "\(DisplayFormat.bytes($0.used)) / \(DisplayFormat.bytes($0.total))" } ?? localized("Unavailable", "暂不可用"), value: { $0.memory?.percent })
                        rowDivider
                        networkRow
                        HStack {
                            Text(localized("60s ago", "60 秒前"))
                            Spacer()
                            Text(localized("Now", "现在"))
                        }.font(.system(size: 9)).foregroundStyle(.tertiary).padding(.top, 2).padding(.bottom, 13)
                    }.padding(.horizontal, 22)
                }
            }.scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider().opacity(0.5)
            HStack {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { settings.toggle() }
                } label: {
                    Image(systemName: settings ? "chevron.left" : "slider.horizontal.3").frame(width: 24, height: 24)
                }.buttonStyle(.plain).help(settings ? localized("Back", "返回") : localized("Preferences", "偏好设置"))
                Text(settings ? localized("Preferences", "偏好设置") : localized("A little clarity. At a glance.", "系统脉动，一目了然。"))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(localized("Quit Pulse", "退出 Pulse"))
                    .keyboardShortcut("q")
            }.padding(.horizontal, 18).padding(.vertical, 9)
        }
        .frame(width: 368, height: height, alignment: .top)
        .background(.regularMaterial)
    }
    private var rowDivider: some View { Divider().opacity(0.35) }
    private func metricRow(_ metric: Metric, current: String, detail: String, value: @escaping (Snapshot) -> Double?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: metric.symbol)
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(metric.color).frame(width: 19, height: 19)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(metric.title).font(.system(size: 12, weight: .medium))
                        Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(current).font(.system(size: 23, weight: .light, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText())
            }.padding(.top, 12)
            TrendChart(samples: store.history.samples, now: store.latest.timestamp, color: metric.color, value: value)
                .frame(height: 28).padding(.top, 5).padding(.bottom, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title), \(current), \(detail)")
    }
    private var networkRow: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: Metric.network.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Metric.network.color).frame(width: 19)
                Text(Metric.network.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(store.latest.network.map { $0.connected ? $0.interfaces.joined(separator: " + ") : localized("No active link", "无活动连接") } ?? localized("Waiting for sample", "等待采样"))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            HStack {
                networkValue("arrow.down", value: store.latest.network?.download, color: Metric.network.color)
                Spacer()
                networkValue("arrow.up", value: store.latest.network?.upload, color: Metric.gpu.color)
            }
            TrendChart(samples: store.history.samples, now: store.latest.timestamp, color: Metric.network.color,
                       value: { $0.network?.download }, secondary: { $0.network?.upload }, percentage: false).frame(height: 29)
        }.padding(.top, 12).padding(.bottom, 8)
    }
    private func networkValue(_ symbol: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            Text(DisplayFormat.rate(value)).font(.system(size: 17, weight: .light, design: .rounded)).monospacedDigit().contentTransition(.numericText())
        }.accessibilityLabel("\(symbol == "arrow.down" ? localized("Download", "下载") : localized("Upload", "上传")), \(DisplayFormat.rate(value))")
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localized("Make room for what matters.", "只留下你关心的信息。"))
                .font(.system(size: 15, weight: .medium))
            VStack(alignment: .leading, spacing: 10) {
                Text(localized("MENU BAR", "菜单栏显示")).font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                ForEach(Metric.allCases) { metric in
                    Toggle(isOn: Binding(get: { preferences.shows(metric) }, set: { preferences.toggle(metric, enabled: $0) })) {
                        Label(metric.title, systemImage: metric.symbol).font(.system(size: 12))
                    }.toggleStyle(.switch).controlSize(.mini)
                }
            }
            Divider()
            Picker(localized("Update every", "刷新间隔"), selection: $preferences.interval) {
                Text(localized("1 second", "1 秒")).tag(1.0)
                Text(localized("2 seconds", "2 秒")).tag(2.0)
                Text(localized("3 seconds", "3 秒")).tag(3.0)
            }.font(.system(size: 12))
            Toggle(localized("Launch at login", "登录时启动"), isOn: Binding(get: { launchAtLogin }, set: updateLogin))
                .toggleStyle(.switch).controlSize(.mini)

            if let loginMessage { Text(loginMessage).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Text(localized("Collected on your Mac. Kept for one minute.\nNo accounts, no uploads, no distractions.", "数据只在本机内存中保留一分钟。\n无账号，无上传，安静常驻。"))
                .font(.system(size: 10)).foregroundStyle(.tertiary).lineSpacing(3)
            Spacer(minLength: 0)
        }.padding(22)
    }
    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? localized("Allow Pulse in System Settings → Login Items.", "请在系统设置 → 登录项中允许 Pulse。") : nil
        } catch {
            loginMessage = localized("Could not update login item. Move Pulse to Applications and retry.", "无法更新登录项。请将 Pulse 移至应用程序后重试。")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

}

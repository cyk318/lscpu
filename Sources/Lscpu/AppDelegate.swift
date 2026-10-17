import AppKit
import SwiftUI
import Combine
import LscpuCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = MonitorStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var lastSignature = ""
    private var compactStatus = false
    private var fullScreenCompact = false
    private var layoutCheckPending = false
    private var screenObserver: NSObjectProtocol?
    private var spaceRefreshes: [DispatchWorkItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Seed only our item's initial placement; existing user placement is preserved.
        let placementKey = "NSStatusItem Preferred Position LscpuStatusItem"
        if UserDefaults.standard.object(forKey: placementKey) == nil {
            UserDefaults.standard.set(0, forKey: placementKey)
        }
        statusItem.autosaveName = "LscpuStatusItem"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Lscpu")
        }
        popover.behavior = CommandLine.arguments.contains("--verify-ui") ? .applicationDefined : .transient
        popover.animates = true
        popover.delegate = self
        store.onUpdate = { [weak self] snapshot in self?.updateStatus(snapshot) }
        store.preferences.$visible.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { guard let self else { return }; self.lastSignature = ""; self.updateStatus(self.store.latest) }
        }.store(in: &subscriptions)
        store.preferences.$interval.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.store.start() }
        }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.popover.performClose(nil); self?.store.sleep()
        })
        for notification in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                // Opening our popover must not expand the status item and displace its anchor.
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self.spaceRefreshes.forEach { $0.cancel() }
                self.spaceRefreshes = [0.4, 1.5, 3.0].map { delay in
                    let refresh = DispatchWorkItem { [weak self] in
                        guard let self, !self.popover.isShown else { return }
                        self.fullScreenCompact = self.frontmostCoversScreen()
                        self.restoreStatusLayout()
                    }
                    // Space notifications can arrive before the destination's windows are
                    // onscreen. Bounded retries handle the transition without ongoing polling.
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: refresh)
                    return refresh
                }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.store.wake() })
        fullScreenCompact = frontmostCoversScreen()
        compactStatus = fullScreenCompact
        updateStatus(store.latest)
        store.start()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.fullScreenCompact = self.frontmostCoversScreen()
            self.restoreStatusLayout()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--capture-previews"), CommandLine.arguments.count > index + 1 {
            let directory = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 64) {
                self.capturePreviews(directory: directory)
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--diagnose-status") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                print("Window behavior: \(String(describing: self.statusItem.button?.window?.collectionBehavior)); on active Space: \(String(describing: self.statusItem.button?.window?.isOnActiveSpace))")
                print("Compact: \(self.compactStatus); status visible: \(self.statusItem.isVisible), button: \(String(describing: self.statusItem.button?.frame)), window: \(String(describing: self.statusItem.button?.window?.frame))")
                for screen in NSScreen.screens { print("Screen: \(screen.frame); right of notch: \(String(describing: screen.auxiliaryTopRightArea))") }
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--verify-ui") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.togglePopover() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard let view = self.popover.contentViewController?.view,
                      let window = view.window, let screen = window.screen else {
                    fputs("FAIL: Popover did not open\n", stderr); exit(1)
                }
                let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
                print("Popover content: \(rect); visible screen: \(screen.visibleFrame)")
                guard screen.visibleFrame.contains(rect) else {
                    fputs("FAIL: Popover content extends outside visible screen\n", stderr); exit(1)
                }
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".build/popover-actual.png"))
                }
                self.popover.performClose(nil)
                print("PASS: Popover opened entirely inside visible screen and closed")
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--show") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.togglePopover() } }
    }
    private func capturePreviews(directory: String) {
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                let view = NSHostingView(rootView: PopoverView(store: store, preferences: store.preferences))
                view.appearance = NSAppearance(named: appearance)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 368, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = view.appearance
                window.contentView = view
                view.setFrameSize(view.fittingSize)
                window.setContentSize(view.fittingSize)
                view.layoutSubtreeIfNeeded()
                view.display()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("pulse-\(name).png"))
                }
            }
        } catch { NSLog("Preview capture failed: %@", error.localizedDescription) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.sleep()
        spaceRefreshes.forEach { $0.cancel() }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        let screen = button.window?.screen ?? NSScreen.main
        let height = min(528, max(240, (screen?.visibleFrame.height ?? 600) - 24))
        let size = NSSize(width: 368, height: height)
        let controller = NSHostingController(rootView: PopoverView(store: store, preferences: store.preferences, height: height))
        // Resolve geometry before showing. Automatic SwiftUI intrinsic resizing can otherwise
        // grow an already-positioned popover upward behind the menu bar.
        controller.sizingOptions = []
        controller.view.setFrameSize(size)
        controller.preferredContentSize = size
        popover.contentViewController = controller
        popover.contentSize = size
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        if CommandLine.arguments.contains("--verify-ui") {
            print("Anchor: \(button.bounds), window: \(String(describing: button.window?.frame)), shown: \(popover.isShown)")
        }
    }
    func popoverDidClose(_ notification: Notification) {
        if CommandLine.arguments.contains("--verify-ui") { print("Popover closed") }
        // Destroy the view tree: closed popovers never lay out or animate charts.
        popover.contentViewController = nil
    }
    private func updateStatus(_ snapshot: Snapshot) {
        struct Segment { let title: String; let value: String; let width: CGFloat }
        var segments: [Segment] = []
        let prefs = store.preferences
        if prefs.shows(.cpu) { segments.append(Segment(title: "CPU", value: DisplayFormat.percent(snapshot.cpu), width: 43)) }
        if prefs.shows(.gpu) { segments.append(Segment(title: "GPU", value: DisplayFormat.percent(snapshot.gpu), width: 43)) }
        if prefs.shows(.memory) { segments.append(Segment(title: "MEM", value: DisplayFormat.percent(snapshot.memory?.percent), width: 43)) }
        if prefs.shows(.network) {
            segments.append(Segment(title: "↓ " + DisplayFormat.rate(snapshot.network?.download), value: "↑ " + DisplayFormat.rate(snapshot.network?.upload), width: 87))
        }
        let accessibility = segments.map { "\($0.title) \($0.value)" }.joined(separator: ", ")
        let signature = "\(compactStatus):" + accessibility
        guard signature != lastSignature || statusItem.button?.image == nil else {
            scheduleStatusLayoutCheck()
            return
        }
        lastSignature = signature
        if compactStatus || segments.isEmpty {
            let icon = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Lscpu")
            icon?.size = NSSize(width: 16, height: 16)
            statusItem.button?.image = icon
        } else {
            let width = segments.reduce(CGFloat(8)) { $0 + $1.width }
            let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
                var x: CGFloat = 4
                for segment in segments {
                    let network = segment.title.hasPrefix("↓")
                    let topFont = NSFont.systemFont(ofSize: network ? 9 : 7, weight: .medium)
                    let bottomFont = NSFont.monospacedDigitSystemFont(ofSize: network ? 9 : 10, weight: .medium)
                    let top = NSAttributedString(string: segment.title, attributes: [.font: topFont, .foregroundColor: NSColor.black])
                    let bottom = NSAttributedString(string: segment.value, attributes: [.font: bottomFont, .foregroundColor: NSColor.black])
                    top.draw(at: NSPoint(x: x + (segment.width - top.size().width) / 2, y: 12))
                    bottom.draw(at: NSPoint(x: x + (segment.width - bottom.size().width) / 2, y: 1))
                    x += segment.width
                }
                return true
            }
            image.isTemplate = true
            statusItem.button?.image = image
        }
        statusItem.button?.toolTip = "Lscpu · " + accessibility
            + (fullScreenCompact ? localized(" · Full screen: click for all metrics", " · 全屏模式，点击查看完整指标")
                : compactStatus ? localized(" · Menu bar space is limited; click for all metrics", " · 菜单栏空间不足，点击查看完整指标") : "")
        statusItem.button?.setAccessibilityValue(accessibility)
        scheduleStatusLayoutCheck()
    }

    /// No Accessibility or Screen Recording permission: only public window bounds,
    /// owner PID and layer are read. Window titles and image contents are not requested.
    /// Also handles apps with their own borderless full-screen implementation.
    private func frontmostCoversScreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return fullScreenCompact }
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return false }
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? Int32 == front.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            for screen in NSScreen.screens {
                let frame = screen.frame
                let top = primary.frame.maxY - frame.maxY
                let menuHeight = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
                if abs(rect.minX - frame.minX) <= 2,
                   abs(rect.width - frame.width) <= 2,
                   rect.minY >= top - 2, rect.minY <= top + menuHeight + 2,
                   rect.maxY >= top + frame.height - 2 {
                    return true
                }
            }
        }
        return false
    }

    private func restoreStatusLayout() {
        compactStatus = fullScreenCompact
        lastSignature = ""
        statusItem.isVisible = true
        updateStatus(store.latest)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreStatusLayout()
        return true
    }

    private func scheduleStatusLayoutCheck() {
        guard !compactStatus, !layoutCheckPending else { return }
        layoutCheckPending = true
        // AppKit positions status items asynchronously after their image size changes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.layoutCheckPending = false
            guard !self.compactStatus, let window = self.statusItem.button?.window,
                  let screen = window.screen else { return }
            // A hidden / transitioning menu bar is not evidence of horizontal overflow.
            // On Tahoe this can be a proxy window: isOnActiveSpace may remain false
            // even while Control Center displays its status-item scene.
            guard window.isVisible else { return }
            let frame = window.frame
            guard frame.minY < screen.frame.maxY, frame.maxY > screen.visibleFrame.maxY else { return }
            // isVisible stays true for items hidden due to insufficient space.
            let usable = screen.auxiliaryTopRightArea ?? screen.frame
            if frame.minX < usable.minX || frame.maxX > usable.maxX {
                self.compactStatus = true
                self.lastSignature = ""
                self.updateStatus(self.store.latest)
            }
        }
    }
}

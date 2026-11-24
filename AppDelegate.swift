import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let settings = Settings.shared
    private let store = LayoutStore.shared
    private let input = InputState()
    private var monitor: InputMonitor!
    private var panel: NSPanel!
    private var host: OverlayHostingView<OverlayView>!
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var retryTimer: Timer?
    private var permissionAlertShown = false
    private var applyingFrame = false

    private static let inputMonitoringURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = InputMonitor(state: input)
        buildWindow()
        buildStatusItem()
        applySettings()

        // Re-layout whenever a setting or the layout changes, or displays are rearranged.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.applySettings() } }
            .store(in: &cancellables)

        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor in self?.applySettings() } }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applySettings() }
        }

        startMonitoring()
    }

    /// Opening the app again from Finder / Spotlight / Launchpad brings the overlay back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.visible = true
        return true
    }

    // MARK: Overlay window

    private func buildWindow() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver            // above normal windows and full-screen apps
        p.ignoresMouseEvents = true       // click-through (turned off while editing)
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.delegate = self

        host = OverlayHostingView(rootView: OverlayView(input: input, settings: settings, store: store))
        host.sizingOptions = []
        p.contentView = host
        panel = p
    }

    /// Called when the user drags the window in "Move Overlay" mode.
    func windowDidMove(_ notification: Notification) {
        guard !applyingFrame, settings.editMode == .move else { return }
        let f = panel.frame
        settings.customTopLeft = CGPoint(x: f.minX, y: f.maxY)
        if settings.position != .custom { settings.position = .custom }
    }

    private func placement(for size: NSSize) -> CGPoint {
        if settings.position == .custom, let tl = settings.customTopLeft {
            let origin = CGPoint(x: tl.x, y: tl.y - size.height)
            let rect = NSRect(origin: origin, size: size)
            // Ignore the saved spot if that display is no longer connected.
            if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) { return origin }
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
        let vf = screen.visibleFrame
        let m: CGFloat = 20
        switch settings.position {
        case .bottomLeft, .custom:
            return CGPoint(x: vf.minX + m, y: vf.minY + m)
        case .bottomRight:
            return CGPoint(x: vf.maxX - size.width - m, y: vf.minY + m)
        case .topLeft:
            return CGPoint(x: vf.minX + m, y: vf.maxY - size.height - m)
        case .topRight:
            return CGPoint(x: vf.maxX - size.width - m, y: vf.maxY - size.height - m)
        case .middleLeft:
            return CGPoint(x: vf.minX + m, y: vf.midY - size.height / 2)
        case .middleRight:
            return CGPoint(x: vf.maxX - size.width - m, y: vf.midY - size.height / 2)
        }
    }

    private func applySettings() {
        let layout = store.layout
        let scale = CGFloat(settings.scale)
        let width = (settings.showMouse ? layout.canvasWidth : layout.keyboardWidth) * scale
        let height = layout.canvasHeight * scale
        let size = NSSize(width: width, height: height)
        let frame = NSRect(origin: placement(for: size), size: size)

        if panel.frame != frame {
            applyingFrame = true
            panel.setFrame(frame, display: true)
            applyingFrame = false
        }

        let mode = settings.editMode
        panel.ignoresMouseEvents = (mode == .off)
        panel.isMovableByWindowBackground = (mode == .move)
        host.allowWindowDrag = (mode == .move)

        if settings.visible || mode != .off {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: Permission

    private func startMonitoring() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()   // shows the system prompt
        }
        if CGPreflightListenEventAccess(), monitor.start() { return }

        if !permissionAlertShown {
            permissionAlertShown = true
            showPermissionAlert()
        }
        // Keep trying so it starts working as soon as access is granted.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.retryStart() }
        }
    }

    private func retryStart() {
        if monitor.isRunning {
            retryTimer?.invalidate()
            retryTimer = nil
        } else if CGPreflightListenEventAccess() {
            monitor.start()
        }
    }

    private func showPermissionAlert() {
        showAlert(
            title: "Input Overlay needs Input Monitoring access",
            text: """
            To show which keys you press, enable Input Overlay under \
            System Settings → Privacy & Security → Input Monitoring.

            If keys don't light up right after you grant it, quit and reopen the app. \
            The app only reads key and mouse-button state to draw the overlay — \
            nothing is recorded or sent anywhere.
            """,
            primary: "Open System Settings"
        ) { [weak self] in self?.openPermissions() }
    }

    private func showAlert(title: String, text: String, primary: String = "OK",
                           onPrimary: (() -> Void)? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: primary)
        if onPrimary != nil { alert.addButton(withTitle: "Later") }
        if alert.runModal() == .alertFirstButtonReturn { onPrimary?() }
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Input Overlay")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !monitor.isRunning {
            menu.addItem(item("⚠️ Grant Input Monitoring access…", #selector(openPermissions)))
            menu.addItem(.separator())
        }

        menu.addItem(item("Show Overlay", #selector(toggleVisible), checked: settings.visible))
        menu.addItem(item("Show Mouse", #selector(toggleMouse), checked: settings.showMouse))
        menu.addItem(.separator())

        // Editing
        menu.addItem(item("Move Overlay", #selector(setEditMode(_:)),
                          checked: settings.editMode == .move, object: "move"))
        menu.addItem(item("Edit Keys (drag to rearrange)", #selector(setEditMode(_:)),
                          checked: settings.editMode == .keys, object: "keys"))
        if settings.editMode != .off {
            menu.addItem(item("✓ Done Editing", #selector(setEditMode(_:)), object: "off"))
        }
        menu.addItem(.separator())

        // Appearance
        var positions = OverlayPosition.allCases.filter { $0 != .custom }.map {
            item($0.title, #selector(setPosition(_:)),
                 checked: settings.position == $0, object: $0.rawValue)
        }
        if settings.position == .custom {
            let custom = NSMenuItem(title: OverlayPosition.custom.title, action: nil, keyEquivalent: "")
            custom.state = .on
            positions.append(custom)
        }
        menu.addItem(submenu("Position", positions))

        menu.addItem(submenu("Size", [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map { (v: Double) in
            item("\(Int(v * 100))%", #selector(setScale(_:)),
                 checked: abs(settings.scale - v) < 0.01, object: v)
        }))

        menu.addItem(submenu("Opacity", [0.3, 0.5, 0.7, 0.85, 1.0].map { (v: Double) in
            item("\(Int(v * 100))%", #selector(setOpacity(_:)),
                 checked: abs(settings.opacity - v) < 0.01, object: v)
        }))

        menu.addItem(submenu("Color", AccentColor.allCases.map {
            item($0.title, #selector(setAccent(_:)),
                 checked: settings.accent == $0, object: $0.rawValue)
        }))

        menu.addItem(submenu("Layout File", [
            item("Open layout.json", #selector(openLayoutFile)),
            item("Reveal in Finder", #selector(revealLayoutFile)),
            item("Reload layout.json", #selector(reloadLayout)),
            item("Reset Layout to Default…", #selector(resetLayout)),
        ]))

        menu.addItem(.separator())
        menu.addItem(item("Launch at Login", #selector(toggleLaunchAtLogin),
                          checked: SMAppService.mainApp.status == .enabled))
        let quit = item("Quit Input Overlay", #selector(quitApp))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, object: Any? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        it.state = checked ? .on : .off
        it.representedObject = object
        return it
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        items.forEach { sub.addItem($0) }
        parent.submenu = sub
        return parent
    }

    // MARK: Actions

    @objc private func toggleVisible() { settings.visible.toggle() }
    @objc private func toggleMouse() { settings.showMouse.toggle() }

    @objc private func setEditMode(_ sender: NSMenuItem) {
        let requested: EditMode
        switch sender.representedObject as? String {
        case "move": requested = .move
        case "keys": requested = .keys
        default:     requested = .off
        }
        // Choosing the active mode again turns editing off.
        settings.editMode = (requested == settings.editMode) ? .off : requested
        if settings.editMode != .off { settings.visible = true }
        if requested == .off || settings.editMode == .off { store.save() }
    }

    @objc private func setPosition(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let p = OverlayPosition(rawValue: raw) {
            settings.position = p
        }
    }

    @objc private func setScale(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? Double { settings.scale = v }
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? Double { settings.opacity = v }
    }

    @objc private func setAccent(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let c = AccentColor(rawValue: raw) {
            settings.accent = c
        }
    }

    @objc private func openLayoutFile() {
        store.save()   // make sure the file exists and is current
        let url = LayoutStore.fileURL
        // Prefer VS Code if it's installed, otherwise the default app for .json files.
        if let vscode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            NSWorkspace.shared.open([url], withApplicationAt: vscode,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func revealLayoutFile() {
        store.save()
        NSWorkspace.shared.activateFileViewerSelecting([LayoutStore.fileURL])
    }

    @objc private func reloadLayout() {
        if let error = store.reload() {
            showAlert(title: "Couldn't read layout.json",
                      text: "Check the JSON syntax. The previous layout is still in use.\n\n\(error)")
        }
    }

    @objc private func resetLayout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Reset layout to the default?"
        alert.informativeText = "This replaces layout.json with the built-in layout."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.resetToDefault() }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    showAlert(title: "Approve Input Overlay in Login Items",
                              text: "Turn on Input Overlay in System Settings → General → Login Items.",
                              primary: "Open Login Items") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }
        } catch {
            showAlert(title: "Couldn't change Launch at Login",
                      text: "Move the app to /Applications and try again.\n\n\(error.localizedDescription)")
        }
    }

    @objc private func openPermissions() {
        if let url = URL(string: Self.inputMonitoringURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

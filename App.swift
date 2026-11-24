import AppKit

@main
struct InputOverlayApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu-bar-only app: no Dock icon, never steals focus.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

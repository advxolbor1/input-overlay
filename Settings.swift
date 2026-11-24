import SwiftUI

enum OverlayPosition: String, CaseIterable {
    case bottomLeft, bottomRight, topLeft, topRight, middleLeft, middleRight, custom

    var title: String {
        switch self {
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        case .middleLeft:  return "Left Edge"
        case .middleRight: return "Right Edge"
        case .custom:      return "Custom (dragged)"
        }
    }
}

enum AccentColor: String, CaseIterable {
    case white, green, cyan, pink, yellow, orange

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .white:  return .white
        case .green:  return Color(red: 0.35, green: 1.00, blue: 0.50)
        case .cyan:   return Color(red: 0.30, green: 0.90, blue: 1.00)
        case .pink:   return Color(red: 1.00, green: 0.45, blue: 0.80)
        case .yellow: return Color(red: 1.00, green: 0.90, blue: 0.30)
        case .orange: return Color(red: 1.00, green: 0.60, blue: 0.20)
        }
    }
}

enum EditMode {
    case off    // normal: overlay is click-through
    case move   // drag the whole overlay around
    case keys   // drag individual keys / the mouse to rearrange them
}

/// User-adjustable options, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var visible: Bool {
        didSet { UserDefaults.standard.set(visible, forKey: "visible") }
    }
    @Published var showMouse: Bool {
        didSet { UserDefaults.standard.set(showMouse, forKey: "showMouse") }
    }
    @Published var scale: Double {
        didSet { UserDefaults.standard.set(scale, forKey: "scale") }
    }
    @Published var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: "opacity") }
    }
    @Published var position: OverlayPosition {
        didSet { UserDefaults.standard.set(position.rawValue, forKey: "position") }
    }
    @Published var accent: AccentColor {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") }
    }
    @Published var editMode: EditMode = .off   // not saved

    /// Where the user dragged the overlay (top-left corner, screen coordinates).
    /// Not @Published on purpose: it changes on every drag step and must not trigger re-layout.
    var customTopLeft: CGPoint? {
        didSet {
            let d = UserDefaults.standard
            if let p = customTopLeft {
                d.set(Double(p.x), forKey: "customX")
                d.set(Double(p.y), forKey: "customTopY")
            } else {
                d.removeObject(forKey: "customX")
                d.removeObject(forKey: "customTopY")
            }
        }
    }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "visible": true,
            "showMouse": true,
            "scale": 1.0,
            "opacity": 0.9,
            "position": OverlayPosition.bottomLeft.rawValue,
            "accent": AccentColor.white.rawValue,
        ])
        visible = d.bool(forKey: "visible")
        showMouse = d.bool(forKey: "showMouse")
        scale = d.double(forKey: "scale")
        opacity = d.double(forKey: "opacity")
        position = OverlayPosition(rawValue: d.string(forKey: "position") ?? "") ?? .bottomLeft
        accent = AccentColor(rawValue: d.string(forKey: "accent") ?? "") ?? .white
        if d.object(forKey: "customX") != nil, d.object(forKey: "customTopY") != nil {
            customTopLeft = CGPoint(x: d.double(forKey: "customX"), y: d.double(forKey: "customTopY"))
        }
    }
}

/// Live state of the keyboard and mouse. Updated by InputMonitor, read by the view.
final class InputState: ObservableObject {
    @Published var pressedKeys: Set<Int> = []
    @Published var left = false
    @Published var right = false
    @Published var middle = false
    @Published var back = false
    @Published var forward = false
    /// 1 = scrolling up, -1 = scrolling down, 0 = idle
    @Published var scroll = 0

    private var scrollReset: DispatchWorkItem?

    func setKey(_ code: Int, down: Bool) {
        if down {
            if !pressedKeys.contains(code) { pressedKeys.insert(code) }
        } else {
            if pressedKeys.contains(code) { pressedKeys.remove(code) }
        }
    }

    /// Modifier keys only arrive as "flags changed" events, so work out press/release here.
    func modifierChanged(code: Int, family: [Int], active: Bool) {
        var keys = pressedKeys
        if !active {
            family.forEach { keys.remove($0) }
        } else if keys.contains(code) {
            keys.remove(code)
        } else {
            keys.insert(code)
        }
        if keys != pressedKeys { pressedKeys = keys }
    }

    func setMouseButton(_ number: Int, down: Bool) {
        switch number {
        case 0: left = down
        case 1: right = down
        case 2: middle = down
        case 3: back = down
        case 4: forward = down
        default: break
        }
    }

    func didScroll(direction: Int) {
        guard direction != 0 else { return }
        scroll = direction
        scrollReset?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scroll = 0 }
        scrollReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    func reset() {
        pressedKeys = []
        left = false; right = false; middle = false
        back = false; forward = false
        scroll = 0
    }
}

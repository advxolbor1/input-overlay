import Foundation
import CoreGraphics

/// Listens (read-only) to global keyboard and mouse events using a CGEventTap.
/// Requires the "Input Monitoring" permission in System Settings > Privacy & Security.
/// The tap never modifies or blocks events, and nothing is stored or sent anywhere.
final class InputMonitor {
    private let state: InputState
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    init(state: InputState) {
        self.state = state
    }

    private static let modifierFlags: [Int: CGEventFlags] = [
        56: .maskShift,      60: .maskShift,        // left / right shift
        59: .maskControl,    62: .maskControl,      // left / right control
        58: .maskAlternate,  61: .maskAlternate,    // left / right option
        55: .maskCommand,    54: .maskCommand,      // left / right command
        57: .maskAlphaShift,                        // caps lock
        63: .maskSecondaryFn,                       // fn
    ]

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        tap = newTap
        source = newSource
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns taps off if they stall; switch it back on and clear any stuck keys.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            state.reset()

        case .keyDown:
            state.setKey(keyCode(event), down: true)

        case .keyUp:
            state.setKey(keyCode(event), down: false)

        case .flagsChanged:
            let code = keyCode(event)
            guard let flag = Self.modifierFlags[code] else { return }
            let family = Self.modifierFlags.filter { $0.value == flag }.map { $0.key }
            state.modifierChanged(code: code, family: family, active: event.flags.contains(flag))

        case .leftMouseDown:  state.setMouseButton(0, down: true)
        case .leftMouseUp:    state.setMouseButton(0, down: false)
        case .rightMouseDown: state.setMouseButton(1, down: true)
        case .rightMouseUp:   state.setMouseButton(1, down: false)

        case .otherMouseDown, .otherMouseUp:
            // 2 = middle, 3 = back, 4 = forward
            let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            state.setMouseButton(number, down: type == .otherMouseDown)

        case .scrollWheel:
            let delta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            state.didScroll(direction: delta > 0 ? 1 : (delta < 0 ? -1 : 0))

        default:
            break
        }
    }

    private func keyCode(_ event: CGEvent) -> Int {
        Int(event.getIntegerValueField(.keyboardEventKeycode))
    }
}

import SwiftUI
import AppKit

// MARK: - Accent color (injected from settings)

private struct AccentKey: EnvironmentKey {
    static let defaultValue = Color.white
}

extension EnvironmentValues {
    var accent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

// MARK: - Hosting view (lets the window be dragged in "Move Overlay" mode)

final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    var allowWindowDrag = false
    override var mouseDownCanMoveWindow: Bool { allowWindowDrag }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Shapes

/// A parallelogram with rounded corners, leaning right like the keys in the reference image.
struct SlantedKeyShape: Shape {
    var slant: CGFloat = 10
    var radius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 2, dy: 2)   // keep the outline inside the frame
        let pts = [
            CGPoint(x: r.minX + slant, y: r.minY),
            CGPoint(x: r.maxX,         y: r.minY),
            CGPoint(x: r.maxX - slant, y: r.maxY),
            CGPoint(x: r.minX,         y: r.maxY),
        ]
        var p = Path()
        let last = pts[pts.count - 1]
        p.move(to: CGPoint(x: (last.x + pts[0].x) / 2, y: (last.y + pts[0].y) / 2))
        for i in 0..<pts.count {
            p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % pts.count], radius: radius)
        }
        p.closeSubpath()
        return p
    }
}

/// A rectangle with an independent radius on each corner (used for the mouse).
struct CornerShape: Shape {
    var tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 2, dy: 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY),
                 tangent2End: CGPoint(x: r.maxX, y: r.minY + tr), radius: tr)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY),
                 tangent2End: CGPoint(x: r.maxX - br, y: r.maxY), radius: br)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY),
                 tangent2End: CGPoint(x: r.minX, y: r.maxY - bl), radius: bl)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY),
                 tangent2End: CGPoint(x: r.minX + tl, y: r.minY), radius: tl)
        p.closeSubpath()
        return p
    }
}

// MARK: - Building blocks

/// Colored outline; filled with the accent color when pressed, see-through dark tint when not.
struct OutlinedShape<S: Shape>: View {
    @Environment(\.accent) private var accent
    let shape: S
    let pressed: Bool

    var body: some View {
        ZStack {
            shape.fill(pressed ? accent : Color.black.opacity(0.35))
            shape.stroke(accent, lineWidth: 2.5)
        }
        .shadow(color: Color.black.opacity(0.5), radius: 2)
        .animation(.easeOut(duration: 0.06), value: pressed)
    }
}

struct KeyView: View {
    @Environment(\.accent) private var accent
    let def: KeyDef
    let pressed: Bool

    var body: some View {
        ZStack {
            OutlinedShape(shape: SlantedKeyShape(), pressed: pressed)
            Text(def.label)
                .font(.custom("AvenirNextCondensed-BoldItalic", size: def.fontSize))
                .foregroundColor(pressed ? Color.black : accent)
        }
        .frame(width: def.w, height: def.h)
    }
}

struct MouseView: View {
    @ObservedObject var input: InputState

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Palm / body
            OutlinedShape(shape: CornerShape(tl: 8, tr: 26, br: 44, bl: 44), pressed: false)
                .frame(width: 176, height: 134)
                .offset(x: 0, y: 116)

            // Left and right buttons
            OutlinedShape(shape: CornerShape(tl: 44, tr: 8, br: 8, bl: 16), pressed: input.left)
                .frame(width: 84, height: 108)
            OutlinedShape(shape: CornerShape(tl: 8, tr: 44, br: 16, bl: 8), pressed: input.right)
                .frame(width: 84, height: 108)
                .offset(x: 92, y: 0)

            // Scroll wheel: filled when clicked; top/bottom half lights up while scrolling
            ZStack {
                OutlinedShape(shape: RoundedRectangle(cornerRadius: 14), pressed: input.middle)
                WheelHighlight(scroll: input.scroll)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .padding(3)
            }
            .frame(width: 30, height: 52)
            .offset(x: 73, y: 38)

            // Side buttons (forward on top, back below)
            OutlinedShape(shape: RoundedRectangle(cornerRadius: 8), pressed: input.forward)
                .frame(width: 24, height: 46)
                .offset(x: 0, y: 128)
            OutlinedShape(shape: RoundedRectangle(cornerRadius: 8), pressed: input.back)
                .frame(width: 24, height: 34)
                .offset(x: 6, y: 182)
        }
        .frame(width: 176, height: 250, alignment: .topLeading)
    }
}

private struct WheelHighlight: View {
    @Environment(\.accent) private var accent
    let scroll: Int

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(scroll > 0 ? accent : Color.clear)
            Rectangle().fill(scroll < 0 ? accent : Color.clear)
        }
    }
}

// MARK: - Drag support for "Edit Keys" mode

struct DragToMove: ViewModifier {
    let enabled: Bool
    let origin: CGPoint
    let onMove: (CGPoint) -> Void
    let onEnd: () -> Void
    @State private var start: CGPoint?

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                .onChanged { value in
                    let s = start ?? origin
                    start = s
                    onMove(CGPoint(x: snap(s.x + value.translation.width),
                                   y: snap(s.y + value.translation.height)))
                }
                .onEnded { _ in
                    start = nil
                    onEnd()
                },
            including: enabled ? .all : .none
        )
    }

    private func snap(_ v: CGFloat) -> CGFloat { (v / 2).rounded() * 2 }
}

// MARK: - Root view

struct OverlayView: View {
    @ObservedObject var input: InputState
    @ObservedObject var settings: Settings
    @ObservedObject var store: LayoutStore

    var body: some View {
        let layout = store.layout
        let scale = CGFloat(settings.scale)
        let width = settings.showMouse ? layout.canvasWidth : layout.keyboardWidth
        let editing = settings.editMode != .off
        let editingKeys = settings.editMode == .keys

        ZStack(alignment: .topLeading) {
            if editing {
                Rectangle().fill(Color.blue.opacity(0.18))
                Rectangle().strokeBorder(Color.blue,
                                         style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }

            ForEach(Array(layout.keys.enumerated()), id: \.offset) { index, key in
                if !key.mouseOnly || settings.showMouse {
                    KeyView(def: key, pressed: !input.pressedKeys.isDisjoint(with: key.codes))
                        .modifier(DragToMove(
                            enabled: editingKeys,
                            origin: CGPoint(x: key.x, y: key.y),
                            onMove: { store.setKeyOrigin(index, to: $0) },
                            onEnd: { store.save() }))
                        .offset(x: key.x, y: key.y)
                }
            }

            if settings.showMouse {
                MouseView(input: input)
                    .modifier(DragToMove(
                        enabled: editingKeys,
                        origin: CGPoint(x: layout.mouseX, y: layout.mouseY),
                        onMove: { store.setMouseOrigin($0) },
                        onEnd: { store.save() }))
                    .offset(x: layout.mouseX, y: layout.mouseY)
            }
        }
        .frame(width: width, height: layout.canvasHeight, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if editing {
                Text(settings.editMode == .move
                     ? "Drag anywhere to move  ·  menu bar ▸ Done Editing"
                     : "Drag keys to rearrange  ·  menu bar ▸ Done Editing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.85))
                    .cornerRadius(6)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "canvas")
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: width * scale, height: layout.canvasHeight * scale, alignment: .topLeading)
        .opacity(editing ? 1.0 : settings.opacity)
        .environment(\.accent, settings.accent.color)
    }
}

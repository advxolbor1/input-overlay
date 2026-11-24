import Foundation
import CoreGraphics

/// One key on the overlay. `codes` are macOS virtual key codes (the key lights up if ANY is pressed).
/// Coordinates are in points on the canvas, origin at the top-left.
struct KeyDef: Identifiable, Codable {
    var label: String
    var codes: [Int]
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var fontSize: CGFloat
    var mouseOnly: Bool      // true = hidden when "Show Mouse" is off

    var id: String { "\(label)-\(Int(x))-\(Int(y))" }

    enum CodingKeys: String, CodingKey {
        case label, codes, x, y, w, h, fontSize, mouseOnly
    }

    init(label: String, codes: [Int], x: CGFloat, y: CGFloat,
         w: CGFloat = 58, h: CGFloat = 54, fontSize: CGFloat = 26, mouseOnly: Bool = false) {
        self.label = label
        self.codes = codes
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.fontSize = fontSize
        self.mouseOnly = mouseOnly
    }

    // Lenient decoding so hand-edited JSON can leave out w / h / fontSize / mouseOnly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        codes = try c.decodeIfPresent([Int].self, forKey: .codes) ?? []
        x = try c.decode(CGFloat.self, forKey: .x)
        y = try c.decode(CGFloat.self, forKey: .y)
        w = try c.decodeIfPresent(CGFloat.self, forKey: .w) ?? 58
        h = try c.decodeIfPresent(CGFloat.self, forKey: .h) ?? 54
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 26
        mouseOnly = try c.decodeIfPresent(Bool.self, forKey: .mouseOnly) ?? false
    }
}

/// The whole overlay layout. Saved as layout.json so you can edit it by hand.
struct LayoutFile: Codable {
    var canvasWidth: CGFloat      // overlay width when the mouse is shown
    var canvasHeight: CGFloat
    var keyboardWidth: CGFloat    // overlay width when the mouse is hidden
    var mouseX: CGFloat
    var mouseY: CGFloat
    var keys: [KeyDef]

    /// The built-in layout (matches the reference screenshot).
    static let standard: LayoutFile = {
        func key(_ label: String, _ codes: [Int], x: CGFloat, row: Int,
                 w: CGFloat = 58, font: CGFloat = 26, mouseOnly: Bool = false) -> KeyDef {
            KeyDef(label: label, codes: codes, x: x, y: CGFloat(row) * 60,
                   w: w, h: 54, fontSize: font, mouseOnly: mouseOnly)
        }
        return LayoutFile(
            canvasWidth: 740, canvasHeight: 300, keyboardWidth: 400,
            mouseX: 432, mouseY: 50,
            keys: [
                key("1", [18], x: 64,  row: 0),
                key("2", [19], x: 128, row: 0),
                key("3", [20], x: 192, row: 0),
                key("4", [21], x: 256, row: 0),
                key("5", [23], x: 320, row: 0),

                key("TAB", [48], x: 0,   row: 1, font: 22),
                key("Q",   [12], x: 64,  row: 1),
                key("W",   [13], x: 128, row: 1),
                key("E",   [14], x: 192, row: 1),
                key("R",   [15], x: 256, row: 1),
                key("T",   [17], x: 320, row: 1),

                key("A", [0], x: 72,  row: 2),
                key("S", [1], x: 136, row: 2),
                key("D", [2], x: 200, row: 2),
                key("F", [3], x: 264, row: 2),
                key("G", [5], x: 328, row: 2),

                key("~", [50], x: 0,   row: 3),
                key("Z", [6],  x: 64,  row: 3),
                key("X", [7],  x: 128, row: 3),
                key("C", [8],  x: 192, row: 3),
                key("V", [9],  x: 256, row: 3),
                key("B", [11], x: 320, row: 3),

                key("CTRL", [59, 62], x: 0,   row: 4, font: 20),
                key("ALT",  [58, 61], x: 128, row: 4, font: 24),
                key("",     [49],     x: 192, row: 4, w: 200),          // space bar
                key("SHIFT", [56, 60], x: 656, row: 4, w: 64, font: 20, mouseOnly: true),
            ]
        )
    }()
}

/// Loads, saves and edits the layout. File: ~/Library/Application Support/InputOverlay/layout.json
final class LayoutStore: ObservableObject {
    static let shared = LayoutStore()

    @Published var layout: LayoutFile

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("InputOverlay", isDirectory: true)
            .appendingPathComponent("layout.json")
    }

    private init() {
        layout = LayoutFile.standard
        if FileManager.default.fileExists(atPath: Self.fileURL.path) {
            _ = reload()
        } else {
            save()
        }
    }

    /// Returns an error message if the file couldn't be read (the current layout is kept).
    @discardableResult
    func reload() -> String? {
        do {
            let data = try Data(contentsOf: Self.fileURL)
            layout = try JSONDecoder().decode(LayoutFile.self, from: data)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func save() {
        do {
            let url = Self.fileURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(layout).write(to: url, options: .atomic)
        } catch {
            NSLog("InputOverlay: could not save layout: \(error)")
        }
    }

    func resetToDefault() {
        layout = LayoutFile.standard
        save()
    }

    func setKeyOrigin(_ index: Int, to p: CGPoint) {
        guard layout.keys.indices.contains(index) else { return }
        layout.keys[index].x = p.x
        layout.keys[index].y = p.y
    }

    func setMouseOrigin(_ p: CGPoint) {
        layout.mouseX = p.x
        layout.mouseY = p.y
    }
}

/*
 Handy macOS key codes (ANSI keyboard), for editing layout.json
 Letters: A0 S1 D2 F3 H4 G5 Z6 X7 C8 V9 B11 Q12 W13 E14 R15 Y16 T17
          O31 U32 I34 P35 L37 J38 K40 N45 M46
 Numbers: 1=18 2=19 3=20 4=21 5=23 6=22 7=26 8=28 9=25 0=29
 Other:   Return 36, Tab 48, Space 49, ` (~) 50, Delete 51, Esc 53
 Arrows:  Left 123, Right 124, Down 125, Up 126
 Mods:    Shift L56 R60, Control L59 R62, Option L58 R61, Command L55 R54, Caps 57, Fn 63
*/

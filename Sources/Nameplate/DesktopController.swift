import AppKit
import NameplateCore

struct DesktopStyle: Equatable {
    var fontFamily: String
    var fontSize: CGFloat
    var fontWeight: String
    var textColor: NSColor
    var opacity: CGFloat
    var shadow: Bool
    var showLabels: Bool
    var position: DesktopPosition
    var screens: ScreenChoice
    var marginX: CGFloat
    var marginY: CGFloat

    private var weight: NSFont.Weight {
        switch fontWeight {
        case "light": return .light
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        default: return .regular
        }
    }

    private var fontManagerWeight: Int {
        switch fontWeight {
        case "light": return 3
        case "medium": return 6
        case "semibold": return 8
        case "bold": return 9
        default: return 5
        }
    }

    @MainActor
    func font(size: CGFloat? = nil, heavier: Bool = false) -> NSFont {
        let pointSize = size ?? fontSize
        var w = weight
        if heavier { w = w.rawValue >= NSFont.Weight.semibold.rawValue ? .heavy : .semibold }
        switch fontFamily {
        case FontChoice.system, "":
            return .systemFont(ofSize: pointSize, weight: w)
        case FontChoice.systemMono:
            return .monospacedSystemFont(ofSize: pointSize, weight: w)
        case FontChoice.systemRounded:
            let base = NSFont.systemFont(ofSize: pointSize, weight: w)
            if let descriptor = base.fontDescriptor.withDesign(.rounded),
               let rounded = NSFont(descriptor: descriptor, size: pointSize) {
                return rounded
            }
            return base
        default:
            let managerWeight = heavier ? min(fontManagerWeight + 3, 11) : fontManagerWeight
            if let font = NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: managerWeight, size: pointSize) {
                return font
            }
            return .systemFont(ofSize: pointSize, weight: w)
        }
    }

    var valueColor: NSColor { textColor.withAlphaComponent(opacity) }
    var labelColor: NSColor { textColor.withAlphaComponent(opacity * 0.62) }

    /// A soft halo in the opposite tone keeps text readable on busy wallpapers.
    var shadowColor: NSColor {
        let rgb = textColor.usingColorSpace(.sRGB) ?? textColor
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.5 ? NSColor(white: 0, alpha: 0.75) : NSColor(white: 1, alpha: 0.7)
    }
}

/// Lays out the lines in two columns (labels right-aligned, values left-aligned)
/// and draws them. Used by the desktop windows.
@MainActor
struct TextBlock {
    struct Piece {
        var text: NSAttributedString
        var origin: CGPoint
    }

    private(set) var pieces: [Piece] = []
    private(set) var size: CGSize = .zero
    static let inset: CGFloat = 6

    init(lines: [InfoLine], style: DesktopStyle, rightAligned: Bool) {
        let shadow: NSShadow? = {
            guard style.shadow else { return nil }
            let s = NSShadow()
            s.shadowColor = style.shadowColor
            s.shadowBlurRadius = max(2, style.fontSize / 5)
            s.shadowOffset = NSSize(width: 0, height: -1)
            return s
        }()
        func attributes(_ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> [NSAttributedString.Key: Any] {
            var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if let shadow { a[.shadow] = shadow }
            if kern != 0 { a[.kern] = kern }
            return a
        }

        let valueAttrs = attributes(style.font(), style.valueColor)
        let labelAttrs = attributes(style.font(), style.labelColor)
        let headerAttrs = attributes(style.font(heavier: true), style.valueColor)
        let sectionAttrs = attributes(style.font(size: max(8, style.fontSize * 0.82), heavier: true), style.labelColor, kern: 1.2)

        let lineGap = round(style.fontSize * 0.28)
        let columnGap = round(style.fontSize * 0.9)
        let showLabels = style.showLabels

        // Measure the label column.
        var labelWidth: CGFloat = 0
        if showLabels {
            for line in lines where line.kind == .row && !line.label.isEmpty {
                labelWidth = max(labelWidth, ceil(NSAttributedString(string: line.label, attributes: labelAttrs).size().width))
            }
        }
        let valueX = showLabels && labelWidth > 0 ? labelWidth + columnGap : 0
        let indent: CGFloat = showLabels ? 0 : round(style.fontSize * 0.8)

        var y: CGFloat = 0
        var width: CGFloat = 0
        var placed: [Piece] = []
        var insideInterface = false
        for line in lines {
            switch line.kind {
            case .spacer:
                y += round(style.fontSize * 0.7)
                insideInterface = false
            case .section:
                if y > 0 { y += round(style.fontSize * 0.5) }
                let text = NSAttributedString(string: line.value.uppercased(), attributes: sectionAttrs)
                placed.append(Piece(text: text, origin: CGPoint(x: 0, y: y)))
                width = max(width, ceil(text.size().width))
                y += ceil(text.size().height) + lineGap
                insideInterface = false
            case .subheader:
                if y > 0 { y += round(style.fontSize * 0.35) }
                let text = NSAttributedString(string: line.value, attributes: headerAttrs)
                placed.append(Piece(text: text, origin: CGPoint(x: 0, y: y)))
                width = max(width, ceil(text.size().width))
                y += ceil(text.size().height) + lineGap
                insideInterface = true
            case .row:
                let value = NSAttributedString(string: line.value, attributes: valueAttrs)
                let valueSize = value.size()
                var rowHeight = ceil(valueSize.height)
                if showLabels && !line.label.isEmpty {
                    let label = NSAttributedString(string: line.label, attributes: labelAttrs)
                    let labelSize = label.size()
                    placed.append(Piece(text: label, origin: CGPoint(x: valueX - columnGap - ceil(labelSize.width), y: y)))
                    rowHeight = max(rowHeight, ceil(labelSize.height))
                }
                let x = showLabels ? valueX : (insideInterface ? indent : 0)
                placed.append(Piece(text: value, origin: CGPoint(x: x, y: y)))
                width = max(width, x + ceil(valueSize.width))
                y += rowHeight + lineGap
            }
        }
        if y > 0 { y -= lineGap }

        // Mirror the layout when the block sits on the right side of the screen.
        if rightAligned && !showLabels {
            placed = placed.map { piece in
                var p = piece
                p.origin.x = width - ceil(piece.text.size().width)
                return p
            }
        }

        let inset = TextBlock.inset
        pieces = placed.map { Piece(text: $0.text, origin: CGPoint(x: $0.origin.x + inset, y: $0.origin.y + inset)) }
        size = CGSize(width: ceil(width) + inset * 2, height: ceil(y) + inset * 2)
    }

    func draw() {
        for piece in pieces { piece.text.draw(at: piece.origin) }
    }
}

/// The view inside each desktop window.
final class InfoTextView: NSView {
    var block: TextBlock? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        block?.draw()
    }
}

/// Puts the information on the desktop: above the wallpaper, below desktop icons
/// and every app window, on every Space, ignoring the mouse.
@MainActor
final class DesktopController {
    private var windows: [NSWindow] = []
    private var lines: [InfoLine] = []
    private var style: DesktopStyle?
    private var enabled = false

    func update(lines: [InfoLine], style: DesktopStyle, enabled: Bool) {
        self.lines = lines
        self.style = style
        self.enabled = enabled
        layout()
    }

    func screensChanged() {
        layout()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.contentView = InfoTextView(frame: window.contentLayoutRect)
        return window
    }

    private func layout() {
        guard enabled, let style, !lines.isEmpty else {
            windows.forEach { $0.orderOut(nil) }
            windows.removeAll()
            return
        }
        let screens = style.screens == .all ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        while windows.count < screens.count { windows.append(makeWindow()) }
        while windows.count > screens.count { windows.removeLast().orderOut(nil) }

        let rightAligned = style.position == .topRight || style.position == .bottomRight
        let block = TextBlock(lines: lines, style: style, rightAligned: rightAligned)
        let size = block.size

        for (window, screen) in zip(windows, screens) {
            let area = screen.visibleFrame
            let inset = TextBlock.inset
            let mx = style.marginX - inset
            let my = style.marginY - inset
            var origin = CGPoint.zero
            switch style.position {
            case .topLeft:
                origin = CGPoint(x: area.minX + mx, y: area.maxY - my - size.height)
            case .topRight:
                origin = CGPoint(x: area.maxX - mx - size.width, y: area.maxY - my - size.height)
            case .bottomLeft:
                origin = CGPoint(x: area.minX + mx, y: area.minY + my)
            case .bottomRight:
                origin = CGPoint(x: area.maxX - mx - size.width, y: area.minY + my)
            }
            let frame = NSRect(origin: origin, size: size).integral
            if window.frame != frame { window.setFrame(frame, display: false) }
            if let view = window.contentView as? InfoTextView {
                view.frame = NSRect(origin: .zero, size: frame.size)
                view.block = block
            }
            window.orderFrontRegardless()
        }
    }
}

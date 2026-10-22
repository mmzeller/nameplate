import AppKit
import SwiftUI
import NameplateCore

struct DesktopStyle: Equatable {
    var fontFamily: String
    var fontSize: CGFloat
    var fontWeight: String
    var textColor: NSColor
    /// nil = the text color, dimmed.
    var labelColor: NSColor?
    /// nil = the label color.
    var headingColor: NSColor?
    var opacity: CGFloat
    var shadow: Bool
    var showLabels: Bool
    var showBars: Bool
    var lineSpacing: CGFloat
    var background: BackgroundStyle
    var backgroundColor: NSColor
    var backgroundOpacity: CGFloat
    var cornerRadius: CGFloat
    var padding: CGFloat
    var screens: ScreenSelection
    /// For displays you haven't positioned the info on yourself.
    var defaultPlacement: Placement
    /// Positions you've set per display, by display key.
    var placements: [String: Placement]
    /// Text sizes you've set per display, by display key. Others use `fontSize`.
    var textSizes: [String: CGFloat]

    /// This style as it applies to one display.
    func forDisplay(_ key: String) -> DesktopStyle {
        guard let size = textSizes[key], size != fontSize else { return self }
        var copy = self
        copy.fontSize = size
        return copy
    }

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

    var labelTextColor: NSColor {
        if let labelColor { return labelColor.withAlphaComponent(opacity) }
        return textColor.withAlphaComponent(opacity * 0.62)
    }

    var headingTextColor: NSColor {
        if let headingColor { return headingColor.withAlphaComponent(opacity) }
        return labelTextColor
    }

    var warnColor: NSColor { NSColor.systemOrange.withAlphaComponent(max(opacity, 0.8)) }

    /// A soft halo in the opposite tone keeps text readable on busy wallpapers.
    var shadowColor: NSColor {
        textColor.luminance > 0.5 ? NSColor(white: 0, alpha: 0.75) : NSColor(white: 1, alpha: 0.7)
    }

    /// Room around the text for its shadow when there's no background panel.
    static let shadowRoom: CGFloat = 6

    /// Space between the window edge and the text: room for the shadow, or the panel's padding.
    var contentInset: CGFloat { background == .off ? DesktopStyle.shadowRoom : padding }

    /// How far the window edge sits outside the margin (so text, not shadow room, lines up with it).
    var edgeOffset: CGFloat { background == .off ? DesktopStyle.shadowRoom : 0 }
}

/// Lays out the lines in two columns (labels right-aligned, values left-aligned), with
/// optional usage bars, and draws them.
@MainActor
struct TextBlock {
    struct Piece {
        var text: NSAttributedString
        var origin: CGPoint
    }

    struct Bar {
        var rect: CGRect
        var fraction: CGFloat
        var warn: Bool
    }

    private(set) var pieces: [Piece] = []
    private(set) var bars: [Bar] = []
    private(set) var size: CGSize = .zero
    private var trackColor = NSColor.clear
    private var fillColor = NSColor.white
    private var warnColor = NSColor.orange
    private var barShadow: NSShadow?

    init(lines: [InfoLine], style: DesktopStyle, rightAligned: Bool) {
        let shadow: NSShadow? = {
            guard style.shadow else { return nil }
            let s = NSShadow()
            s.shadowColor = style.shadowColor
            s.shadowBlurRadius = max(2, style.fontSize / 5)
            s.shadowOffset = NSSize(width: 0, height: -1)
            return s
        }()
        func attributes(_ font: NSFont, _ color: NSColor) -> [NSAttributedString.Key: Any] {
            var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if let shadow { a[.shadow] = shadow }
            return a
        }

        let valueAttrs = attributes(style.font(), style.valueColor)
        let labelAttrs = attributes(style.font(), style.labelTextColor)
        let subheaderAttrs = attributes(style.font(heavier: true), style.valueColor)
        let headingAttrs = attributes(style.font(size: round(style.fontSize * 1.08), heavier: true), style.headingTextColor)

        let lineGap = max(0, round(style.fontSize * 0.28 * style.lineSpacing))
        let columnGap = round(style.fontSize * 0.9)
        let barWidth = round(style.fontSize * 5)
        let barHeight = max(4, round(style.fontSize * 0.42))
        let barGap = round(style.fontSize * 0.6)
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

        struct Row {
            var pieces: [Piece]
            var bars: [Bar]
            var width: CGFloat
        }
        var rows: [Row] = []
        var y: CGFloat = 0

        for line in lines {
            switch line.kind {
            case .spacer:
                y += round(style.fontSize * 0.7 * max(style.lineSpacing, 0.5))
            case .section:
                if y > 0 { y += round(style.fontSize * 0.45) }
                let text = NSAttributedString(string: line.value, attributes: headingAttrs)
                let textSize = text.size()
                rows.append(Row(pieces: [Piece(text: text, origin: CGPoint(x: 0, y: y))], bars: [], width: ceil(textSize.width)))
                y += ceil(textSize.height) + lineGap
            case .subheader:
                if y > 0 { y += round(style.fontSize * 0.35) }
                let text = NSAttributedString(string: line.value, attributes: subheaderAttrs)
                let textSize = text.size()
                rows.append(Row(pieces: [Piece(text: text, origin: CGPoint(x: 0, y: y))], bars: [], width: ceil(textSize.width)))
                y += ceil(textSize.height) + lineGap
            case .row:
                var rowPieces: [Piece] = []
                let value = NSAttributedString(string: line.value, attributes: valueAttrs)
                let valueSize = value.size()
                var height = ceil(valueSize.height)
                if showLabels && !line.label.isEmpty {
                    let label = NSAttributedString(string: line.label, attributes: labelAttrs)
                    let labelSize = label.size()
                    rowPieces.append(Piece(text: label, origin: CGPoint(x: valueX - columnGap - ceil(labelSize.width), y: y)))
                    height = max(height, ceil(labelSize.height))
                }
                let x = showLabels ? valueX : (line.isInterfaceDetail ? indent : 0)
                rowPieces.append(Piece(text: value, origin: CGPoint(x: x, y: y)))
                var end = x + ceil(valueSize.width)
                var rowBars: [Bar] = []
                if style.showBars, let fraction = line.fraction {
                    let rect = CGRect(x: end + barGap, y: y + round((height - barHeight) / 2), width: barWidth, height: barHeight)
                    rowBars.append(Bar(rect: rect, fraction: CGFloat(min(max(fraction, 0), 1)), warn: line.warn))
                    end = rect.maxX
                }
                rows.append(Row(pieces: rowPieces, bars: rowBars, width: end))
                y += height + lineGap
            }
        }
        if y > 0 { y -= lineGap }
        let width = rows.map { $0.width }.max() ?? 0

        // On the right side of the screen, line rows up on the right edge (when there's no label column).
        if rightAligned && !showLabels {
            for index in rows.indices {
                let shift = width - rows[index].width
                guard shift > 0 else { continue }
                for p in rows[index].pieces.indices { rows[index].pieces[p].origin.x += shift }
                for b in rows[index].bars.indices { rows[index].bars[b].rect.origin.x += shift }
            }
        }

        pieces = rows.flatMap { $0.pieces }
        bars = rows.flatMap { $0.bars }
        size = CGSize(width: ceil(width), height: ceil(max(y, 0)))
        trackColor = style.valueColor.withAlphaComponent(style.opacity * 0.25)
        fillColor = style.valueColor
        warnColor = style.warnColor
        barShadow = shadow
    }

    func draw() {
        if !bars.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            barShadow?.set()
            for bar in bars {
                let radius = bar.rect.height / 2
                trackColor.setFill()
                NSBezierPath(roundedRect: bar.rect, xRadius: radius, yRadius: radius).fill()
                var filled = bar.rect
                filled.size.width = max(bar.rect.height, bar.rect.width * bar.fraction)
                (bar.warn ? warnColor : fillColor).setFill()
                NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        for piece in pieces { piece.text.draw(at: piece.origin) }
    }
}

/// Draws the text block.
final class InfoTextView: NSView {
    var block: TextBlock? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        block?.draw()
    }
}

/// The dashed outline shown while you're moving the info.
final class MoveOutlineView: NSView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}

/// Everything inside a desktop window: optional background, the text, and the move outline.
final class DesktopContentView: NSView {
    let textView = InfoTextView()
    private let outline = MoveOutlineView()
    private var solidView: NSView?
    private var blurView: NSVisualEffectView?
    private var tintView: NSView?
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?

    /// The display this copy of the info belongs to.
    var displayKey = ""
    /// When set, dragging stays inside this area (each display keeps its own copy).
    var dragLimit: NSRect?
    var isDragging: Bool { dragStartMouse != nil }
    var onMoved: ((NSWindow, String) -> Void)?
    var isMoving = false {
        didSet {
            outline.isHidden = !isMoving
            window?.invalidateCursorRects(for: self)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(textView)
        outline.isHidden = true
        addSubview(outline)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    @MainActor
    func apply(block: TextBlock, style: DesktopStyle) {
        let inset = style.contentInset
        textView.frame = NSRect(x: inset, y: inset, width: block.size.width, height: block.size.height)
        textView.block = block
        outline.frame = bounds

        switch style.background {
        case .off:
            solidView?.removeFromSuperview()
            solidView = nil
            blurView?.removeFromSuperview()
            blurView = nil
            tintView = nil
        case .solid:
            blurView?.removeFromSuperview()
            blurView = nil
            tintView = nil
            let view = solidView ?? NSView()
            if solidView == nil {
                view.wantsLayer = true
                addSubview(view, positioned: .below, relativeTo: textView)
                solidView = view
            }
            view.frame = bounds
            view.layer?.backgroundColor = style.backgroundColor.withAlphaComponent(style.backgroundOpacity).cgColor
            view.layer?.cornerRadius = style.cornerRadius
        case .blur:
            solidView?.removeFromSuperview()
            solidView = nil
            let view = blurView ?? NSVisualEffectView()
            if blurView == nil {
                view.blendingMode = .behindWindow
                view.state = .active
                view.material = .popover
                let tint = NSView()
                tint.wantsLayer = true
                tint.autoresizingMask = [.width, .height]
                view.addSubview(tint)
                addSubview(view, positioned: .below, relativeTo: textView)
                blurView = view
                tintView = tint
            }
            view.appearance = NSAppearance(named: style.backgroundColor.luminance < 0.5 ? .darkAqua : .aqua)
            view.frame = bounds
            view.maskImage = DesktopContentView.roundedMask(radius: style.cornerRadius)
            tintView?.frame = view.bounds
            tintView?.layer?.backgroundColor = style.backgroundColor.withAlphaComponent(style.backgroundOpacity).cgColor
            tintView?.layer?.cornerRadius = style.cornerRadius
        }
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = max(radius, 1) * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Moving

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isMoving else { return nil }
        return frame.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        if isMoving { addCursorRect(bounds, cursor: .openHand) }
    }

    override func mouseDown(with event: NSEvent) {
        guard isMoving, let window else { return }
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window.frame.origin
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMoving, let window, let startMouse = dragStartMouse, let startOrigin = dragStartOrigin else { return }
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: startOrigin.x + mouse.x - startMouse.x, y: startOrigin.y + mouse.y - startMouse.y)
        if let limit = dragLimit {
            origin = Placement.clamp(origin, size: window.frame.size, in: limit)
        }
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        guard isMoving, let window, dragStartMouse != nil else { return }
        NSCursor.pop()
        dragStartMouse = nil
        dragStartOrigin = nil
        onMoved?(window, displayKey)
    }
}

/// Puts the information on the desktop: above the wallpaper, below desktop icons
/// and every app window, on every Space, ignoring the mouse (except while you move it).
/// Each display gets its own window and its own position.
@MainActor
final class DesktopController {
    private var windows: [String: NSWindow] = [:]   // by display key
    private var lines: [InfoLine] = []
    private var style: DesktopStyle?
    private var enabled = false
    private var donePanel: NSPanel?

    private(set) var isMoving = false
    /// Called after a drag with the display, its new position, and (when the info was
    /// dragged onto another display) the new choice of display to show it on.
    var onMoveFinished: ((String, Placement, ScreenSelection?) -> Void)?

    func update(lines: [InfoLine], style: DesktopStyle, enabled: Bool) {
        self.lines = lines
        self.style = style
        self.enabled = enabled
        if !enabled && isMoving { endMove() }
        layout()
    }

    func screensChanged() {
        layout()
    }

    // MARK: Moving

    func beginMove() {
        guard enabled, !isMoving else { return }
        isMoving = true
        layout()
        showDonePanel()
    }

    func endMove() {
        guard isMoving else { return }
        isMoving = false
        donePanel?.orderOut(nil)
        donePanel = nil
        layout()
    }

    private func showDonePanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 70),
                            styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Move Desktop Info"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let several = style?.screens == .every && windows.count > 1
        panel.contentView = NSHostingView(rootView: MoveHelpView(eachDisplay: several, done: { [weak self] in self?.endMove() }))
        // Put the instructions on the display where the info is.
        if let screen = windows.values.first?.screen ?? NSScreen.screens.first {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.maxY - panel.frame.height - 40))
        }
        panel.orderFrontRegardless()
        donePanel = panel
    }

    /// The displays that should show the info right now.
    private func targets(for style: DesktopStyle) -> [Displays.Info] {
        let displays = Displays.all()
        switch style.screens {
        case .every:
            return displays
        case .menuBarDisplay:
            return Array(displays.prefix(1))
        case .display(let key):
            let match = displays.filter { $0.key == key }
            // If that display isn't connected, fall back to the one with the menu bar.
            return match.isEmpty ? Array(displays.prefix(1)) : match
        }
    }

    private func windowMoved(_ window: NSWindow, displayKey: String) {
        guard let style else { return }
        let frame = window.frame
        var newSelection: ScreenSelection?
        let target: Displays.Info?
        if style.screens == .every {
            // Each display has its own copy, and dragging kept it on its display.
            target = Displays.all().first { $0.key == displayKey }
        } else {
            // One copy: it goes to whichever display you dropped it on.
            target = Displays.info(containing: NSPoint(x: frame.midX, y: frame.midY))
            if let target, target.key != targets(for: style).first?.key {
                newSelection = target.hasMenuBar ? .menuBarDisplay : .display(target.key)
            }
        }
        guard let target else { return }
        let area = target.screen.visibleFrame
        let onScreen = NSRect(origin: Placement.clamp(frame.origin, size: frame.size, in: area), size: frame.size)
        let placement = Placement.nearest(to: onScreen, in: area, edgeOffset: style.edgeOffset)

        // Use the new spot right away, so nothing flickers back while the setting saves.
        var updated = style
        updated.placements[target.key] = placement
        if let newSelection { updated.screens = newSelection }
        self.style = updated
        layout()
        onMoveFinished?(target.key, placement, newSelection)
    }

    // MARK: Windows

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = DesktopController.desktopLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        let content = DesktopContentView(frame: window.contentLayoutRect)
        content.onMoved = { [weak self] movedWindow, displayKey in
            self?.windowMoved(movedWindow, displayKey: displayKey)
        }
        window.contentView = content
        return window
    }

    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)

    private func layout() {
        guard enabled, let style, !lines.isEmpty else {
            windows.values.forEach { $0.orderOut(nil) }
            windows.removeAll()
            return
        }
        let targets = targets(for: style)
        let wanted = Set(targets.map { $0.key })
        for (key, window) in windows where !wanted.contains(key) {
            window.orderOut(nil)
            windows[key] = nil
        }

        let inset = style.contentInset
        // Displays with the same text size and alignment share one layout.
        var blocks: [String: TextBlock] = [:]
        for target in targets {
            let window = windows[target.key] ?? makeWindow()
            windows[target.key] = window
            guard let content = window.contentView as? DesktopContentView else { continue }

            let displayStyle = style.forDisplay(target.key)
            let placement = style.placements[target.key] ?? style.defaultPlacement
            let rightAligned = placement.isRightAligned
            let blockKey = "\(rightAligned)-\(displayStyle.fontSize)"
            let block = blocks[blockKey] ?? TextBlock(lines: lines, style: displayStyle, rightAligned: rightAligned)
            blocks[blockKey] = block
            let size = CGSize(width: block.size.width + inset * 2, height: block.size.height + inset * 2)
            let area = target.screen.visibleFrame

            content.displayKey = target.key
            content.dragLimit = style.screens == .every ? area : nil
            if content.isDragging {
                // Never pull it out from under the pointer; just let it grow or shrink in place.
                var frame = window.frame
                if frame.size != size {
                    frame.origin.y += frame.height - size.height
                    frame.size = size
                    window.setFrame(frame, display: false)
                }
            } else {
                let frame = placement.frame(for: size, in: area, edgeOffset: style.edgeOffset)
                if window.frame != frame { window.setFrame(frame, display: false) }
            }
            content.frame = NSRect(origin: .zero, size: window.frame.size)
            content.apply(block: block, style: displayStyle)
            if content.isMoving != isMoving { content.isMoving = isMoving }
            window.ignoresMouseEvents = !isMoving
            window.level = isMoving ? .floating : DesktopController.desktopLevel
            window.orderFrontRegardless()
        }
    }
}

private struct MoveHelpView: View {
    let eachDisplay: Bool
    let done: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.draw")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(eachDisplay
                 ? "Drag the info on each display to where you want it."
                 : "Drag the info where you want it, even onto another display.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Done") { done() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 400)
    }
}

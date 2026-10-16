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

    /// Space between the window edge and the text: room for the shadow, or the panel's padding.
    var contentInset: CGFloat { background == .off ? TextBlock.shadowRoom : padding }

    /// How far the window edge sits outside the margin (so text, not shadow room, lines up with it).
    var edgeOffset: CGFloat { background == .off ? TextBlock.shadowRoom : 0 }
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

    static let shadowRoom: CGFloat = 6

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
        var insideInterface = false

        for line in lines {
            switch line.kind {
            case .spacer:
                y += round(style.fontSize * 0.7 * max(style.lineSpacing, 0.5))
                insideInterface = false
            case .section:
                if y > 0 { y += round(style.fontSize * 0.45) }
                let text = NSAttributedString(string: line.value, attributes: headingAttrs)
                let textSize = text.size()
                rows.append(Row(pieces: [Piece(text: text, origin: CGPoint(x: 0, y: y))], bars: [], width: ceil(textSize.width)))
                y += ceil(textSize.height) + lineGap
                insideInterface = false
            case .subheader:
                if y > 0 { y += round(style.fontSize * 0.35) }
                let text = NSAttributedString(string: line.value, attributes: subheaderAttrs)
                let textSize = text.size()
                rows.append(Row(pieces: [Piece(text: text, origin: CGPoint(x: 0, y: y))], bars: [], width: ceil(textSize.width)))
                y += ceil(textSize.height) + lineGap
                insideInterface = true
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
                let x = showLabels ? valueX : (insideInterface ? indent : 0)
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

    var onMoved: ((NSWindow) -> Void)?
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
        window.setFrameOrigin(NSPoint(x: startOrigin.x + mouse.x - startMouse.x, y: startOrigin.y + mouse.y - startMouse.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard isMoving, let window, dragStartMouse != nil else { return }
        NSCursor.pop()
        dragStartMouse = nil
        dragStartOrigin = nil
        onMoved?(window)
    }
}

/// Puts the information on the desktop: above the wallpaper, below desktop icons
/// and every app window, on every Space, ignoring the mouse (except while you move it).
@MainActor
final class DesktopController {
    private var windows: [NSWindow] = []
    private var lines: [InfoLine] = []
    private var style: DesktopStyle?
    private var enabled = false
    private var donePanel: NSPanel?

    private(set) var isMoving = false
    /// Called after a drag with the nearest corner and the margins from it.
    var onMoveFinished: ((DesktopPosition, CGFloat, CGFloat) -> Void)?

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
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 70),
                            styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Move Desktop Info"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: MoveHelpView(done: { [weak self] in self?.endMove() }))
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.maxY - panel.frame.height - 40))
        }
        panel.orderFrontRegardless()
        donePanel = panel
    }

    private func windowMoved(_ window: NSWindow) {
        guard let style, let screen = window.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let frame = window.frame
        let left = frame.minX - area.minX
        let right = area.maxX - frame.maxX
        let bottom = frame.minY - area.minY
        let top = area.maxY - frame.maxY
        let isLeft = left <= right
        let isBottom = bottom <= top
        let position: DesktopPosition = isBottom ? (isLeft ? .bottomLeft : .bottomRight) : (isLeft ? .topLeft : .topRight)
        let marginX = max(0, (isLeft ? left : right) + style.edgeOffset)
        let marginY = max(0, (isBottom ? bottom : top) + style.edgeOffset)
        onMoveFinished?(position, round(marginX), round(marginY))
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
        content.onMoved = { [weak self] movedWindow in
            self?.windowMoved(movedWindow)
        }
        window.contentView = content
        return window
    }

    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)

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
        let inset = style.contentInset
        let size = CGSize(width: block.size.width + inset * 2, height: block.size.height + inset * 2)

        for (window, screen) in zip(windows, screens) {
            let area = screen.visibleFrame
            let mx = style.marginX - style.edgeOffset
            let my = style.marginY - style.edgeOffset
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
            if let content = window.contentView as? DesktopContentView {
                content.frame = NSRect(origin: .zero, size: frame.size)
                content.apply(block: block, style: style)
                if content.isMoving != isMoving { content.isMoving = isMoving }
            }
            window.ignoresMouseEvents = !isMoving
            window.level = isMoving ? .floating : DesktopController.desktopLevel
            window.orderFrontRegardless()
        }
    }
}

private struct MoveHelpView: View {
    let done: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.draw")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Drag the info to where you want it.")
            Spacer(minLength: 0)
            Button("Done") { done() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 360)
    }
}

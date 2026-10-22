import CoreGraphics
import Foundation

public enum DesktopPosition: String, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    public var title: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}

/// Where the desktop info sits on one display: a corner and the distance from it.
public struct Placement: Equatable, Sendable {
    public var corner: DesktopPosition
    /// Distance from the left or right edge, in points.
    public var x: CGFloat
    /// Distance from the top or bottom edge (menu bar and Dock excluded), in points.
    public var y: CGFloat

    public init(corner: DesktopPosition, x: CGFloat, y: CGFloat) {
        self.corner = corner
        self.x = x
        self.y = y
    }

    public init?(dictionary: [String: Any]) {
        guard let raw = dictionary["corner"] as? String, let corner = DesktopPosition(rawValue: raw) else { return nil }
        let x = (dictionary["x"] as? NSNumber)?.doubleValue ?? 28
        let y = (dictionary["y"] as? NSNumber)?.doubleValue ?? 28
        self.init(corner: corner, x: CGFloat(max(0, x)), y: CGFloat(max(0, y)))
    }

    public var dictionary: [String: Any] {
        ["corner": corner.rawValue, "x": Double(x), "y": Double(y)]
    }

    public var isRightAligned: Bool { corner == .topRight || corner == .bottomRight }

    /// The window frame for something of `size` on a display whose usable area is `area`.
    /// Always kept fully on that display.
    public func frame(for size: CGSize, in area: CGRect, edgeOffset: CGFloat) -> CGRect {
        let mx = x - edgeOffset
        let my = y - edgeOffset
        let origin: CGPoint
        switch corner {
        case .topLeft: origin = CGPoint(x: area.minX + mx, y: area.maxY - my - size.height)
        case .topRight: origin = CGPoint(x: area.maxX - mx - size.width, y: area.maxY - my - size.height)
        case .bottomLeft: origin = CGPoint(x: area.minX + mx, y: area.minY + my)
        case .bottomRight: origin = CGPoint(x: area.maxX - mx - size.width, y: area.minY + my)
        }
        return CGRect(origin: Placement.clamp(origin, size: size, in: area), size: size).integral
    }

    /// The placement that keeps a window at `frame`, measured from the nearest corner of `area`.
    public static func nearest(to frame: CGRect, in area: CGRect, edgeOffset: CGFloat) -> Placement {
        let left = frame.minX - area.minX
        let right = area.maxX - frame.maxX
        let bottom = frame.minY - area.minY
        let top = area.maxY - frame.maxY
        let isLeft = left <= right
        let isBottom = bottom <= top
        let corner: DesktopPosition = isBottom ? (isLeft ? .bottomLeft : .bottomRight) : (isLeft ? .topLeft : .topRight)
        return Placement(corner: corner,
                         x: max(0, ((isLeft ? left : right) + edgeOffset).rounded()),
                         y: max(0, ((isBottom ? bottom : top) + edgeOffset).rounded()))
    }

    /// Keeps something of `size` inside `area`. If it's bigger than the area, its top-left stays visible.
    public static func clamp(_ origin: CGPoint, size: CGSize, in area: CGRect) -> CGPoint {
        CGPoint(x: max(area.minX, min(origin.x, area.maxX - size.width)),
                y: min(area.maxY - size.height, max(origin.y, area.minY)))
    }
}

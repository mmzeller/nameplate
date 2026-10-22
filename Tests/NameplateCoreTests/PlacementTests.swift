import XCTest
import CoreGraphics
import NameplateCore

/// Positions on two displays like a MacBook screen and an LG ultrawide.
/// macOS measures every display in one shared space, so a monitor to the left of
/// the laptop has negative coordinates.
final class PlacementTests: XCTestCase {
    /// Usable area of a MacBook screen (menu bar removed).
    let macBook = CGRect(x: 0, y: 0, width: 1512, height: 944)
    /// Usable area of an ultrawide to the left of it, sitting a little lower.
    let ultrawide = CGRect(x: -3440, y: -200, width: 3440, height: 1415)
    let size = CGSize(width: 320, height: 240)

    func testEachCornerComesBackTheSameOnBothDisplays() {
        for (name, area) in [("MacBook", macBook), ("ultrawide", ultrawide)] {
            for corner in DesktopPosition.allCases {
                let placement = Placement(corner: corner, x: 40, y: 60)
                let frame = placement.frame(for: size, in: area, edgeOffset: 6)
                XCTAssertTrue(area.contains(frame), "\(corner) on \(name) went off screen: \(frame)")
                XCTAssertEqual(Placement.nearest(to: frame, in: area, edgeOffset: 6), placement, "\(corner) on \(name)")
            }
        }
        print("RESULT placement: all four corners land on screen and save back unchanged on both displays")
    }

    func testDroppingAnywhereSavesThatExactSpot() {
        // Wherever you let go, saving and redrawing puts it back in the same place.
        for area in [macBook, ultrawide] {
            for fx in stride(from: 0.0, through: 1.0, by: 0.125) {
                for fy in stride(from: 0.0, through: 1.0, by: 0.125) {
                    let origin = CGPoint(x: (area.minX + (area.width - size.width) * fx).rounded(),
                                         y: (area.minY + (area.height - size.height) * fy).rounded())
                    let dropped = CGRect(origin: origin, size: size)
                    let saved = Placement.nearest(to: dropped, in: area, edgeOffset: 6)
                    let redrawn = saved.frame(for: size, in: area, edgeOffset: 6)
                    XCTAssertEqual(redrawn, dropped, "dropped at \(origin)")
                }
            }
        }
        print("RESULT placement: 162 drop spots across both displays redraw exactly where they were dropped")
    }

    func testWideMonitorSpotStaysOnTheLaptopScreen() {
        // 2,800 points from the left suits the ultrawide but is wider than the laptop screen.
        let placement = Placement(corner: .bottomLeft, x: 2800, y: 30)
        let onLaptop = placement.frame(for: size, in: macBook, edgeOffset: 6)
        XCTAssertTrue(macBook.contains(onLaptop), "\(onLaptop)")
        XCTAssertEqual(onLaptop.maxX, macBook.maxX)
        let onUltrawide = placement.frame(for: size, in: ultrawide, edgeOffset: 6)
        XCTAssertTrue(ultrawide.contains(onUltrawide))
        XCTAssertEqual(onUltrawide.minX, ultrawide.minX + 2794)
    }

    func testTooBigForTheScreenKeepsTheTopLeftVisible() {
        let frame = Placement(corner: .bottomRight, x: 0, y: 0)
            .frame(for: CGSize(width: 2000, height: 1200), in: macBook, edgeOffset: 0)
        XCTAssertEqual(frame.minX, macBook.minX)
        XCTAssertEqual(frame.maxY, macBook.maxY)
    }

    func testSavedPositionsSurviveStorage() {
        let placement = Placement(corner: .topRight, x: 123, y: 45)
        XCTAssertEqual(Placement(dictionary: placement.dictionary), placement)
        XCTAssertNil(Placement(dictionary: ["corner": "middle"]))
        XCTAssertEqual(Placement(dictionary: ["corner": "topLeft", "x": -50])?.x, 0)
    }
}

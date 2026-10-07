import SnapshotTesting
import SwiftUI
import XCTest

/// How much of the golden a snapshot covers.
enum SnapshotFrame {
    /// The view at its own size, for markers, rows and sheets.
    case fitting
    /// A whole iPhone 17 Pro screen, safe areas and bars included.
    case phone
}

/// Light and dark goldens of one view, named `<test>.<name>-light/-dark`.
/// Rendered on the pinned simulator only (tools/check.sh ios); anti-aliasing differs on any other.
@MainActor
func assertLightAndDark<V: View>(
    _ view: V,
    named name: String,
    frame: SnapshotFrame = .fitting,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    for style in [UIUserInterfaceStyle.light, .dark] {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.userInterfaceIdiom = .phone
            traits.displayScale = 3
        }
        let controller = UIHostingController(rootView: view)
        let size: CGSize
        let safeArea: UIEdgeInsets
        switch frame {
        case .fitting:
            size = controller.sizeThatFits(in: CGSize(width: 402, height: CGFloat.greatestFiniteMagnitude))
            safeArea = .zero
        case .phone:
            size = CGSize(width: 402, height: 874)
            safeArea = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        }
        ensureKeyWindow()
        // Drawn off-screen, the glass controls lose their thumbs, edges and bar titles; a real window draws them.
        let window = Snapshotting<UIViewController, UIImage>.image(
            on: ViewImageConfig(safeArea: safeArea, size: size, traits: traits),
            drawHierarchyInKeyWindow: true,
            precision: 0.999,
            perceptualPrecision: 0.98
        )
        // A window render keeps the wide colour range a PNG drops; compare it the way the golden was stored.
        let strategy = Snapshotting<UIViewController, UIImage>(
            pathExtension: window.pathExtension,
            diffing: window.diffing,
            asyncSnapshot: { window.snapshot($0).map(\.asStoredPNG) }
        )
        assertSnapshot(
            of: controller,
            as: strategy,
            named: "\(name)-\(style == .dark ? "dark" : "light")",
            file: file,
            testName: testName,
            line: line
        )
    }
}

private var keyWindow: UIWindow?

/// The test host draws no screen of its own, so the first window is ours.
@MainActor
private func ensureKeyWindow() {
    guard keyWindow == nil else { return }
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
        XCTFail("the test host has no window scene to draw in")
        return
    }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    keyWindow = window
}

private extension UIImage {
    var asStoredPNG: UIImage {
        guard let data = pngData(), let stored = UIImage(data: data, scale: scale) else { return self }
        return stored
    }
}

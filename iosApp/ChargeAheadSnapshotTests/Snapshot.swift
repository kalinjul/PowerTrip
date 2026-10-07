import SnapshotTesting
import SwiftUI
import XCTest

/// How much of the golden a snapshot covers.
enum SnapshotFrame {
    /// The view at its own size, for markers, rows and sheets.
    case fitting
    /// A whole screen on an iPhone 17 Pro, safe areas and bars included.
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
        // On the controller, not only in the traits: UIKit's bars read the style from there.
        let controller = UIHostingController(rootView: view.preferredColorScheme(style == .dark ? .dark : .light))
        controller.overrideUserInterfaceStyle = style
        let strategy: Snapshotting<UIViewController, UIImage>
        switch frame {
        case .fitting:
            strategy = .image(precision: 0.999, perceptualPrecision: 0.98, size: controller.sizeThatFits(in: CGSize(width: 402, height: CGFloat.greatestFiniteMagnitude)), traits: traits)
        case .phone:
            let iPhone17Pro = ViewImageConfig(
                safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
                size: CGSize(width: 402, height: 874),
                traits: traits
            )
            ensureKeyWindow()
            // Off-screen layer rendering leaves the glass bars' titles blank; a real window draws them.
            strategy = .image(on: iPhone17Pro, drawHierarchyInKeyWindow: true, precision: 0.999, perceptualPrecision: 0.98)
        }
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
    guard keyWindow == nil,
          let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    keyWindow = window
}

import UIKit

// Screens that hide the navigation bar for a custom header lose UIKit's edge-swipe back
// gesture; re-enabling it here keeps swipe-to-go-back working on those screens.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

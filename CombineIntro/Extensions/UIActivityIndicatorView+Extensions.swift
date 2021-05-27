import UIKit

extension UIActivityIndicatorView {
    var writableIsAnimating: Bool {
        get { isAnimating }
        set {
            if newValue {
                startAnimating()
            } else {
                stopAnimating()
            }
        }
    }
}

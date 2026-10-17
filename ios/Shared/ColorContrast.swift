import SwiftUI
import UIKit

extension Color {
    /// 배경색 대비가 좋은 전경색 (밝은 배경 → 검정, 어두운/채도 높은 배경 → 흰색)
    var contrastingForeground: Color {
        UIColor(self).contrastingForeground.swiftUIColor
    }
}

extension UIColor {
    var contrastingForeground: UIColor {
        isLightBackground ? UIColor(white: 0, alpha: 1) : UIColor(white: 1, alpha: 1)
    }

    var isLightBackground: Bool {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if getRed(&r, green: &g, blue: &b, alpha: &a) {
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return luminance > 0.6
        }
        var white: CGFloat = 0
        if getWhite(&white, alpha: &a) {
            return white > 0.6
        }
        return false
    }

    var swiftUIColor: Color { Color(self) }
}

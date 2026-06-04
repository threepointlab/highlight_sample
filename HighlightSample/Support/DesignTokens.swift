import SwiftUI

// Minimal stubs matching Cliff's design system signatures.
// Real values: Spacing = 4pt grid, AppColor = dark palette, AppFont = SF Pro.

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs:  CGFloat = 4
    static let s:   CGFloat = 8
    static let m:   CGFloat = 12
    static let l:   CGFloat = 16
}

enum AppColor {
    enum BG {
        static let primary = Color.black
    }
    enum Surface {
        static let placeholder = Color(white: 0.15)
    }
    enum Text {
        static let primary = Color.white
        static let muted   = Color(red: 0.67, green: 0.67, blue: 0.67) // #AAAAAA
    }
}

enum AppFont {
    static let caption: Font = .system(size: 12, weight: .regular)
}

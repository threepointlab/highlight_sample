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
    enum Accent {
        static let brand = Color.yellow // Cliff actual: brand yellow-orange
    }
}

// step4+ 에서 ResultHighlightsView 가 사용
extension Spacing {
    static let xl: CGFloat = 24
}

enum AppFont {
    static let caption: Font = .system(size: 12, weight: .regular)
}

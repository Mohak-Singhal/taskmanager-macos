import SwiftUI

enum D {
    enum FontSize {
        static let title: CGFloat = 22
        static let section: CGFloat = 16
        static let body: CGFloat = 13
        static let secondary: CGFloat = 12
        static let caption: CGFloat = 11
    }

    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let badge: CGFloat = 8
    }

    enum Padding {
        static let screen: CGFloat = 16
        static let card: CGFloat = 12
        static let control: CGFloat = 8
    }

    enum Control {
        static let height: CGFloat = 28
        static let barHeight: CGFloat = 32
        static let minWidth: CGFloat = 44
    }

    enum Icon {
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 18
    }
}

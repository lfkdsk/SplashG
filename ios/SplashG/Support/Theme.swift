import SwiftUI

enum Theme {
    static let bg = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let card = Color(white: 0.13)
    static let accent = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let subtle = Color.white.opacity(0.55)
    static let titleGradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.83, blue: 1.0), Color(red: 0.23, green: 0.47, blue: 0.98)],
        startPoint: .leading, endPoint: .trailing)
}

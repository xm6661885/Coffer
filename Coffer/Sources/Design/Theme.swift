import SwiftUI

extension Color {
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")
    static let surfaceSunken = Color("SurfaceSunken")
    static let ink = Color("Ink")
    static let inkSecondary = Color("InkSecondary")
    static let inkTertiary = Color("InkTertiary")
    static let hairline = Color("Hairline")
    static let pink = Color("Pink")
    static let pinkInk = Color("PinkInk")
    static let pinkSoft = Color("PinkSoft")
    static let onPink = Color("OnPink")
    static let danger = Color("Danger")
    static let success = Color("Success")
}

extension Font {
    static let cofferLargeTitle = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let cofferTitle = Font.system(.title2, design: .serif).weight(.semibold)
    static let cofferHeadline = Font.system(.headline, design: .serif)
    static let cofferBody = Font.system(.body)
    static let cofferCallout = Font.system(.callout)
    static let cofferCaption = Font.system(.caption)
    static let cofferMono = Font.system(.callout, design: .monospaced)
    static let cofferTimecode = Font.system(.caption, design: .monospaced).monospacedDigit()
}

extension View {
    func paperList() -> some View { scrollContentBackground(.hidden).background(Color.canvas).listRowSeparatorTint(.hairline) }
}

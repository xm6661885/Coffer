import SwiftUI
import CoreText

struct FontPreview: View {
    let url: URL
    @State private var fontName: String?
    @State private var fullName = "Font"
    @State private var hasSample = false
    private let glyphSample = "\u{6C38}\u{548C}\u{4E5D}\u{5E74}\u{FF0C}\u{5C81}\u{5728}\u{7678}\u{4E11}"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(fullName).font(.cofferTitle)
                if let fontName {
                    ForEach([16.0, 24, 36, 56], id: \.self) { size in Text("The quick brown fox jumps over the lazy dog").font(.custom(fontName, size: size)) }
                    Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789").font(.custom(fontName, size: 24))
                    if hasSample { Text(glyphSample).font(.custom(fontName, size: 24)) }
                } else { ContentUnavailableView("No preview available", systemImage: "textformat") }
            }.foregroundStyle(Color.ink).padding(20)
        }.background(Color.canvas)
            .task {
                let sample = glyphSample
                let result = await Task.detached { () -> (String, String, Bool)? in
                    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let descriptor = descriptors.first else { return nil }
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                    let font = CTFontCreateWithFontDescriptor(descriptor, 24, nil)
                    var characters = Array(sample.utf16); var glyphs = [CGGlyph](repeating: 0, count: characters.count)
                    let supported = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
                    return (CTFontCopyPostScriptName(font) as String, CTFontCopyFullName(font) as String, supported)
                }.value
                if let result { fontName = result.0; fullName = result.1; hasSample = result.2 }
            }
    }
}

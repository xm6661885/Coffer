import SwiftUI
struct Scrubber: View {
    enum Style { case music, video }
    var current: Double; var duration: Double; var buffered: Double? = nil
    var onScrubbingChanged: (Bool) -> Void = { _ in }; var onSeek: (Double) -> Void; var style: Style = .music
    var onPreviewTime: (Double?) -> Void = { _ in }
    var showsTimePreview = true
    @State private var dragging = false
    @State private var value = 0.0
    @State private var previousX: CGFloat?
    @State private var fine = false
    private var shown: Double { dragging ? value : current }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(style == .music ? Color.ink.opacity(0.1) : Color.white.opacity(0.3))
                if let buffered { Capsule().fill(style == .music ? Color.ink.opacity(0.15) : Color.white.opacity(0.5)).frame(width: geometry.size.width * min(1, max(0, buffered / max(1, duration)))) }
                Capsule().fill(Color.pink).frame(width: geometry.size.width * min(1, max(0, shown / max(1, duration))))
            }.frame(height: dragging ? (style == .music ? 12 : 10) : (style == .music ? 6 : 4)).frame(maxHeight: .infinity)
                .overlay(alignment: .top) { if dragging && showsTimePreview { VStack(spacing: 2) { Text(Formatters.duration(value)); if fine { Text("Fine scrubbing").font(.caption2) } }.font(.cofferTimecode).foregroundStyle(style == .music ? Color.ink : Color.white).padding(10).glassEffect(.regular, in: .capsule).offset(y: -44) } }
                .contentShape(.rect).gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    if !dragging { dragging = true; value = max(0, min(duration, Double(event.location.x / max(1, geometry.size.width)) * duration)); previousX = event.location.x; onScrubbingChanged(true) }
                    fine = event.translation.height < -60
                    if let previousX { value = max(0, min(duration, value + Double((event.location.x - previousX) / max(1, geometry.size.width)) * duration * (fine ? 0.25 : 1))) }; previousX = event.location.x; onPreviewTime(value)
                }.onEnded { _ in onSeek(value); dragging = false; previousX = nil; onScrubbingChanged(false); onPreviewTime(nil) }).animation(.snappy, value: dragging)
        }.frame(height: 44).accessibilityElement().accessibilityLabel("Playback position").accessibilityValue("\(Formatters.duration(shown)) of \(Formatters.duration(duration))").accessibilityAdjustableAction { direction in onSeek(max(0, min(duration, current + (direction == .increment ? 10 : -10)))) }
    }
}

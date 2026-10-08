import SwiftUI

struct VideoScrubPreview: View {
    let model: VideoPlayerModel
    let time: Double
    @State private var image: UIImage?
    private var bucket: Int { Int(max(0, time) / 2) }
    var body: some View {
        VStack(spacing: 4) {
            Color.black.aspectRatio(16.0 / 9.0, contentMode: .fit).overlay {
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                else { Image(systemName: "film").foregroundStyle(.white.opacity(0.6)) }
            }.clipShape(.rect(cornerRadius: 8))
            Text(Formatters.duration(time)).font(.cofferTimecode).foregroundStyle(.white)
        }.padding(6).background(.black.opacity(0.85), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2), lineWidth: 0.5) }
            .task(id: model.current.id + ":" + String(bucket)) {
                image = nil
                try? await Task.sleep(for: .milliseconds(120)); guard !Task.isCancelled else { return }
                let result = await model.scrubThumbnail(at: min(Double(bucket) * 2, max(0, model.duration - 0.1)))
                if !Task.isCancelled { image = result }
            }
    }
}

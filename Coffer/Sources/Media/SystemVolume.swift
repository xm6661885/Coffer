import MediaPlayer
import AVFAudio

@MainActor final class SystemVolume {
    let view = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
    var onChange: ((Float) -> Void)?
    private var observation: NSKeyValueObservation?
    init() {
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let value = session.outputVolume
            Task { @MainActor in self?.onChange?(value) }
        }
    }
    var value: Float { AVAudioSession.sharedInstance().outputVolume }
    func set(_ value: Float) { guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }; slider.setValue(max(0, min(1, value)), animated: false); slider.sendActions(for: .valueChanged); slider.sendActions(for: .touchUpInside) }
}

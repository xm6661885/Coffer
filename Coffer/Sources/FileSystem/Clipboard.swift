import Foundation
import Observation

@MainActor @Observable final class Clipboard {
    enum Mode { case copy, cut }
    private(set) var items: [FileItem] = []
    private(set) var mode: Mode = .copy
    var isEmpty: Bool { items.isEmpty }
    func set(_ items: [FileItem], mode: Mode) { self.items = items; self.mode = mode }
    func clear() { items.removeAll() }
}

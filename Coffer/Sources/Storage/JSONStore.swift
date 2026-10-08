import Foundation

private enum JSONPersistence { static let queue = DispatchQueue(label: "app.coffer.json", qos: .utility) }
struct JSONStore<Value: Codable> {
    let fileName: String
    var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Coffer").appending(path: fileName) }
    func load(default defaultValue: Value) -> Value { guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Value.self, from: data) else { return defaultValue }; return value }
    func saveAndWait(_ value: Value) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            JSONPersistence.queue.async {
                do { let data = try JSONEncoder().encode(value); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: url, options: .atomic); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func save(_ value: Value) {
        JSONPersistence.queue.async {
            do { let data = try JSONEncoder().encode(value); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: url, options: .atomic) }
            catch { NotificationCenter.default.post(name: .cofferPersistenceFailed, object: error) }
        }
    }
}
extension Notification.Name { static let cofferPersistenceFailed = Notification.Name("cofferPersistenceFailed") }

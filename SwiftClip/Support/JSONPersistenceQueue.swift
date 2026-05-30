import Foundation

final class JSONPersistenceQueue {
    private let queue: DispatchQueue

    init(label: String) {
        queue = DispatchQueue(label: label, qos: .utility)
    }

    func write<Value: Encodable & Sendable>(
        _ value: Value,
        to fileURL: URL,
        encodeDatesAsISO8601: Bool = false,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        queue.async {
            do {
                try FileLocations.ensureBaseDirectories()
                let encoder = JSONEncoder()
                if encodeDatesAsISO8601 {
                    encoder.dateEncodingStrategy = .iso8601
                }
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(value)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                onError(error)
            }
        }
    }

    func flush() {
        queue.sync {}
    }
}

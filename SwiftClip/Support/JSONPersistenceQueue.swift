import Foundation

final class JSONPersistenceQueue: @unchecked Sendable {
    private typealias WriteOperation = @Sendable () -> Void

    private let queue: DispatchQueue
    private var debounceGeneration = 0
    private var pendingDebouncedWrite: WriteOperation?

    init(label: String) {
        queue = DispatchQueue(label: label, qos: .utility)
    }

    func write<Value: Encodable & Sendable>(
        _ value: Value,
        to fileURL: URL,
        encodeDatesAsISO8601: Bool = false,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        enqueueImmediately {
            Self.performWrite(
                value,
                to: fileURL,
                encodeDatesAsISO8601: encodeDatesAsISO8601,
                completion: { result in
                    if case .failure(let error) = result {
                        onError(error)
                    }
                }
            )
        }
    }

    func write<Value: Encodable & Sendable>(
        _ value: Value,
        to fileURL: URL,
        encodeDatesAsISO8601: Bool = false,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        enqueueImmediately {
            Self.performWrite(
                value,
                to: fileURL,
                encodeDatesAsISO8601: encodeDatesAsISO8601,
                completion: completion
            )
        }
    }

    func writeDebounced<Value: Encodable & Sendable>(
        _ value: Value,
        to fileURL: URL,
        encodeDatesAsISO8601: Bool = false,
        delay: TimeInterval = 0.25,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        let operation: WriteOperation = {
            Self.performWrite(
                value,
                to: fileURL,
                encodeDatesAsISO8601: encodeDatesAsISO8601,
                completion: { result in
                    if case .failure(let error) = result {
                        onError(error)
                    }
                }
            )
        }

        queue.async { [self] in
            debounceGeneration &+= 1
            let generation = debounceGeneration
            pendingDebouncedWrite = operation

            queue.asyncAfter(deadline: .now() + max(0, delay)) { [self] in
                guard generation == debounceGeneration,
                      let pendingDebouncedWrite else {
                    return
                }

                self.pendingDebouncedWrite = nil
                pendingDebouncedWrite()
            }
        }
    }

    func writeAndWait<Value: Encodable & Sendable>(
        _ value: Value,
        to fileURL: URL,
        encodeDatesAsISO8601: Bool = false
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            write(
                value,
                to: fileURL,
                encodeDatesAsISO8601: encodeDatesAsISO8601
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    func flush() {
        queue.sync { [self] in
            guard let pendingDebouncedWrite else {
                return
            }

            debounceGeneration &+= 1
            self.pendingDebouncedWrite = nil
            pendingDebouncedWrite()
        }
    }

    private func enqueueImmediately(_ operation: @escaping WriteOperation) {
        queue.async { [self] in
            debounceGeneration &+= 1
            pendingDebouncedWrite = nil
            operation()
        }
    }

    private static func performWrite<Value: Encodable & Sendable>(
        _ value: Value,
        to fileURL: URL,
        encodeDatesAsISO8601: Bool,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            if encodeDatesAsISO8601 {
                encoder.dateEncodingStrategy = .iso8601
            }
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
}

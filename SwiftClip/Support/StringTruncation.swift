import Foundation

extension String {
    func swiftClipTruncated(to limit: Int) -> String {
        guard limit > 0 else {
            return ""
        }

        guard count > limit else {
            return self
        }

        let visibleCount = max(0, limit - 3)
        return String(prefix(visibleCount)) + "..."
    }
}

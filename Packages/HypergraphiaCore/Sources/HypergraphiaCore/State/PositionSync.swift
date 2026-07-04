import Foundation

public struct PreviewSourceAnchor: Hashable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int
    public let progress: Double

    public var approximateLine: Double {
        let span = max(0, endLine - startLine)
        return Double(startLine) + (Double(span) * progress)
    }
}

/// Dead-simple scroll position bridge between editor and preview, keyed per window.
public enum ScrollBridge {
    private static var fractions: [String: Double] = [:]

    public static func fraction(for id: String) -> Double {
        fractions[id] ?? 0
    }

    public static func setFraction(_ value: Double, for id: String) {
        fractions[id] = value
    }

    /// Drop a retired key. Windows re-key on every save/rename, so without
    /// cleanup the map accumulates one stranded entry per rename for the
    /// life of the process.
    public static func clear(for id: String) {
        fractions[id] = nil
    }
}

/// Stores current text selection per window so the destination view can highlight it on mode switch.
public enum SelectionBridge {
    private static var selections: [String: String] = [:]

    public static func selection(for id: String) -> String? {
        selections[id]
    }

    public static func setSelection(_ text: String?, for id: String) {
        if let text, !text.isEmpty {
            selections[id] = text
        } else {
            selections[id] = nil
        }
    }

    /// Drop a retired key (see `ScrollBridge.clear`). Selections can hold
    /// multi-kilobyte strings, so stranded entries are worth reclaiming.
    public static func clear(for id: String) {
        selections[id] = nil
    }
}

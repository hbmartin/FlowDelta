import Foundation

public struct StableID: RawRepresentable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty)
        self.rawValue = rawValue
    }

    public init(namespace: String, components: some Sequence<String>) {
        let canonical = components.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        let first = StableDigest.fnv1a64(namespace + "|" + canonical, seed: 0xcbf29ce484222325)
        let second = StableDigest.fnv1a64(canonical + "|" + namespace, seed: 0x84222325cbf29ce4)
        rawValue = "\(namespace):\(String(first, radix: 16)):" + String(second, radix: 16)
    }

    public var description: String { rawValue }

    public static func < (lhs: StableID, rhs: StableID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum StableDigest {
    public static func fnv1a64(_ value: String, seed: UInt64 = 0xcbf29ce484222325) -> UInt64 {
        value.utf8.reduce(seed) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x100000001b3
        }
    }

    public static func hex(_ value: String) -> String {
        String(fnv1a64(value), radix: 16)
    }
}

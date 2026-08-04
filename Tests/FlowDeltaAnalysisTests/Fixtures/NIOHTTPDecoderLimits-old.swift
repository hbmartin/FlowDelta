/// Exact source excerpt from apple/swift-nio 404f73261919151cfcd93ee46aa9b1ab0be4ef4a.
public struct NIOHTTPDecoderLimitConfiguration: Sendable, Hashable {
    public var maxHeaderFieldSize: Int
    public var maxHeaderListSize: Int
    public var maxHeaderFieldCount: Int

    public init() {
        maxHeaderFieldSize = 80 * 1024
        maxHeaderListSize = 16384 * 128
        maxHeaderFieldCount = 256
    }
}

/// Exact source excerpt from apple/swift-nio eeb20e7f958f608064360d16542d16bf3219170c.
public struct NIOHTTPDecoderLimitConfiguration: Sendable, Hashable {
    public var maxHeaderFieldSize: Int
    public var maxHeaderListSize: Int
    public var maxHeaderFieldCount: Int

    public init() {
        maxHeaderFieldSize = 80 * 1024
        maxHeaderListSize = 80 * 1024
        maxHeaderFieldCount = Int(UInt16.max) - 1
    }
}

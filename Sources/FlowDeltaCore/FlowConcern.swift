/// What kind of change a concern group holds.
public enum FlowConcernKind: String, Codable, CaseIterable, Sendable {
    /// Changes that can change behavior.
    case behavioral
    /// Renames, moves and equivalent rewrites.
    case refactoring
    /// Formatting and optional-syntax changes.
    case cosmetic
}

/// Why two changed entities are in the same concern group.
public enum FlowConcernLinkReason: String, Codable, CaseIterable, Sendable {
    /// One calls the other.
    case call
    /// One's new body names the other.
    case reference
    /// Neither had another link, and both are in the same file and type.
    case sameType
    /// A type changed only inside members that changed.
    case container

    public var displayName: String {
        switch self {
        case .call: "calls"
        case .reference: "refers to"
        case .sameType: "is in the same type as"
        case .container: "contains"
        }
    }
}

public struct FlowConcernLink: Codable, Hashable, Sendable {
    public let from: StableID
    public let to: StableID
    public let reason: FlowConcernLinkReason

    public init(from: StableID, to: StableID, reason: FlowConcernLinkReason) {
        self.from = from
        self.to = to
        self.reason = reason
    }
}

/// A group of entity changes that belong to one concern of a revision.
public struct FlowConcern: Codable, Hashable, Sendable, Identifiable {
    public let id: StableID
    public let kind: FlowConcernKind
    public let title: String
    /// The members' entity IDs (`EntityChange.entityID`), in path and source order.
    public let memberIDs: [StableID]
    /// The links that put the members together.
    public let links: [FlowConcernLink]

    public init(id: StableID, kind: FlowConcernKind, title: String, memberIDs: [StableID], links: [FlowConcernLink]) {
        self.id = id
        self.kind = kind
        self.title = title
        self.memberIDs = memberIDs
        self.links = links
    }
}

public extension EntityChange {
    /// The ID of the entity on the target side, or on the base side for a removal.
    var entityID: StableID? {
        new?.id ?? old?.id
    }
}

public extension RevisionFlowDeltaReport {
    /// Whether the revision mixes two or more behavioral concerns.
    var isTangled: Bool {
        (concerns ?? []).count { $0.kind == .behavioral } >= 2
    }

    /// The concern group that holds `change`, if the report has concerns.
    func concern(containing change: EntityChange) -> FlowConcern? {
        guard let id = change.entityID else { return nil }
        return concerns?.first { $0.memberIDs.contains(id) }
    }
}

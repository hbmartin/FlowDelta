import FlowDeltaCore
import Foundation
import OSLog

public struct EntityMatcherConfiguration: Sendable, Hashable {
    public var fuzzyTokenThreshold: Double

    public init(fuzzyTokenThreshold: Double = 0.80) {
        self.fuzzyTokenThreshold = fuzzyTokenThreshold
    }
}

public struct EntityTriage: Sendable, Hashable {
    public let matches: [EntityMatch]
    public let changes: [EntityChange]

    public init(matches: [EntityMatch], changes: [EntityChange]) {
        self.matches = matches
        self.changes = changes
    }
}

public struct EntityMatcher: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Match")
    public let configuration: EntityMatcherConfiguration

    public init(configuration: EntityMatcherConfiguration = .init()) {
        self.configuration = configuration
    }

    public func triage(old oldEntities: [SourceEntity], new newEntities: [SourceEntity]) -> EntityTriage {
        var unmatchedOld = Dictionary(uniqueKeysWithValues: oldEntities.map { ($0.id, $0) })
        var unmatchedNew = Dictionary(uniqueKeysWithValues: newEntities.map { ($0.id, $0) })
        var matches: [EntityMatch] = []

        matchExactNames(old: &unmatchedOld, new: &unmatchedNew, matches: &matches)
        matchStructuralHashes(old: &unmatchedOld, new: &unmatchedNew, matches: &matches)
        matchFuzzyTokens(old: &unmatchedOld, new: &unmatchedNew, matches: &matches)

        var changes = matches.map(change(for:))
        changes.append(contentsOf: unmatchedOld.values.map {
            EntityChange(kind: .removed, old: $0, new: nil, confidence: nil)
        })
        changes.append(contentsOf: unmatchedNew.values.map {
            EntityChange(kind: .added, old: nil, new: $0, confidence: nil)
        })
        changes.sort(by: changeOrder)
        Self.logger.debug(
            "Triaged entities: \(matches.count) matched, \(unmatchedOld.count) removed, \(unmatchedNew.count) added"
        )
        return EntityTriage(matches: matches.sorted(by: matchOrder), changes: changes)
    }

    private func matchExactNames(
        old: inout [StableID: SourceEntity],
        new: inout [StableID: SourceEntity],
        matches: inout [EntityMatch]
    ) {
        let candidates = candidatePairs(old: old.values, new: new.values) {
            $0.kind == $1.kind && $0.qualifiedName == $1.qualifiedName
        }
        consumeUnique(candidates, tier: .exactName, score: 1, old: &old, new: &new, matches: &matches)
    }

    private func matchStructuralHashes(
        old: inout [StableID: SourceEntity],
        new: inout [StableID: SourceEntity],
        matches: inout [EntityMatch]
    ) {
        let candidates = candidatePairs(old: old.values, new: new.values) {
            $0.kind == $1.kind && $0.body.structuralDigest == $1.body.structuralDigest
        }
        consumeUnique(candidates, tier: .structuralHash, score: 0.95, old: &old, new: &new, matches: &matches)
    }

    private func matchFuzzyTokens(
        old: inout [StableID: SourceEntity],
        new: inout [StableID: SourceEntity],
        matches: inout [EntityMatch]
    ) {
        var scored: [(SourceEntity, SourceEntity, Double)] = []
        for oldEntity in old.values {
            for newEntity in new.values where oldEntity.kind == newEntity.kind {
                let score = Self.tokenDice(oldEntity.body.normalizedTokens, newEntity.body.normalizedTokens)
                if score >= configuration.fuzzyTokenThreshold {
                    scored.append((oldEntity, newEntity, score))
                }
            }
        }
        scored.sort {
            if $0.2 != $1.2 { return $0.2 > $1.2 }
            return ($0.0.path, $0.0.qualifiedName, $0.1.path, $0.1.qualifiedName)
                < ($1.0.path, $1.0.qualifiedName, $1.1.path, $1.1.qualifiedName)
        }
        for (oldEntity, newEntity, score) in scored {
            guard old.removeValue(forKey: oldEntity.id) != nil,
                  new.removeValue(forKey: newEntity.id) != nil
            else { continue }
            matches.append(EntityMatch(
                old: oldEntity,
                new: newEntity,
                confidence: MatchConfidence(tier: .fuzzyTokens, score: score)
            ))
        }
    }

    private func candidatePairs(
        old: some Collection<SourceEntity>,
        new: some Collection<SourceEntity>,
        predicate: (SourceEntity, SourceEntity) -> Bool
    ) -> [(SourceEntity, SourceEntity)] {
        var candidates: [(SourceEntity, SourceEntity)] = []
        for oldEntity in old {
            for newEntity in new where predicate(oldEntity, newEntity) {
                candidates.append((oldEntity, newEntity))
            }
        }
        return candidates.sorted {
            ($0.0.path, $0.0.qualifiedName, $0.1.path, $0.1.qualifiedName)
                < ($1.0.path, $1.0.qualifiedName, $1.1.path, $1.1.qualifiedName)
        }
    }

    private func consumeUnique(
        _ candidates: [(SourceEntity, SourceEntity)],
        tier: MatchTier,
        score: Double,
        old: inout [StableID: SourceEntity],
        new: inout [StableID: SourceEntity],
        matches: inout [EntityMatch]
    ) {
        for (oldEntity, newEntity) in candidates {
            guard old.removeValue(forKey: oldEntity.id) != nil,
                  new.removeValue(forKey: newEntity.id) != nil
            else { continue }
            matches.append(EntityMatch(
                old: oldEntity,
                new: newEntity,
                confidence: MatchConfidence(tier: tier, score: score)
            ))
        }
    }

    private func change(for match: EntityMatch) -> EntityChange {
        let kind: EntityChangeKind
        if match.old.qualifiedName != match.new.qualifiedName {
            kind = .renamed
        } else if match.old.path != match.new.path {
            kind = .moved
        } else if match.old.body.structuralDigest != match.new.body.structuralDigest {
            kind = .modified
        } else {
            kind = .unchanged
        }
        return EntityChange(kind: kind, old: match.old, new: match.new, confidence: match.confidence)
    }

    private func matchOrder(_ lhs: EntityMatch, _ rhs: EntityMatch) -> Bool {
        (lhs.new.path, lhs.new.range.start, lhs.new.qualifiedName)
            < (rhs.new.path, rhs.new.range.start, rhs.new.qualifiedName)
    }

    private func changeOrder(_ lhs: EntityChange, _ rhs: EntityChange) -> Bool {
        let left = lhs.new ?? lhs.old!
        let right = rhs.new ?? rhs.old!
        return (left.path, left.range.start, left.qualifiedName)
            < (right.path, right.range.start, right.qualifiedName)
    }

    static func tokenDice(_ lhs: [String], _ rhs: [String]) -> Double {
        if lhs.isEmpty && rhs.isEmpty { return 1 }
        var leftCounts = lhs.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        var intersection = 0
        for token in rhs where leftCounts[token, default: 0] > 0 {
            intersection += 1
            leftCounts[token, default: 0] -= 1
        }
        return (2 * Double(intersection)) / Double(lhs.count + rhs.count)
    }
}

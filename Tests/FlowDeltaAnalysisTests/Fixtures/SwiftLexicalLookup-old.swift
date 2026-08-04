// Exact source excerpt from swiftlang/swift-syntax 58b966582ddd632593afb6101a147740c244ec89.
extension ProtocolDeclSyntax {
  public func lookup(
    _ identifier: Identifier?,
    at lookUpPosition: AbsolutePosition,
    with config: LookupConfig
  ) -> [LookupResult] {
    var results: [LookupResult] = []

    if let primaryAssociatedTypeClause,
      primaryAssociatedTypeClause.range.contains(lookUpPosition)
    {
      results = memberBlock.lookupAssociatedTypeDeclarations(
        identifier,
        at: lookUpPosition,
        with: config
      )
    }

    let lookInMembers: [LookupResult]

    if inheritanceClause?.range.contains(lookUpPosition) != false {
      lookInMembers = [.lookForMembers(in: Syntax(self))]
    } else {
      lookInMembers = []
    }

    return results
      + defaultLookupImplementation(
        identifier,
        at: lookUpPosition,
        with: config,
        propagateToParent: false
      ) + lookInMembers + lookupInParent(identifier, at: lookUpPosition, with: config)
  }
}

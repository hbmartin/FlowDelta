// Exact source excerpt from swiftlang/swift-syntax 39d18d4b9960adf8bf01026a5471c98d62fa3f64.
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

    // Don't look for members if we're in the inheritance clause
    if inheritanceClause?.range.contains(lookUpPosition) == true {
      lookInMembers = []
    } else {
      lookInMembers = [.lookForMembers(in: Syntax(self))]
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

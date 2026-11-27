/// How a review shows the selected function.
public enum FlowReviewPresentation: Int, CaseIterable, Codable, Sendable {
    /// One merged graph of the function's flow delta.
    case delta
    /// The base and target graphs side by side.
    case beforeAfter
    /// The call-graph neighborhood of the function.
    case calls
}

/// Which way a slice follows causality from the selected node.
public enum FlowSliceDirection: Int, CaseIterable, Codable, Sendable {
    case forward
    case backward
}

/// What a host can observe and restore about a review.
public struct FlowReviewState: Hashable, Codable, Sendable {
    public var presentation: FlowReviewPresentation
    /// The active slice direction, or nil when no slice is shown.
    public var slice: FlowSliceDirection?
    /// The display name of the selected function, or nil when the selected row is not callable.
    public var selectedFunctionName: String?
    /// The stable ID of the selected graph node.
    public var selectedNodeStableID: String?

    public init(
        presentation: FlowReviewPresentation = .delta,
        slice: FlowSliceDirection? = nil,
        selectedFunctionName: String? = nil,
        selectedNodeStableID: String? = nil
    ) {
        self.presentation = presentation
        self.slice = slice
        self.selectedFunctionName = selectedFunctionName
        self.selectedNodeStableID = selectedNodeStableID
    }
}

/// Who changed a review's state. Hosts persist preferences only for changes the user made.
public enum FlowReviewChangeCause: Sendable {
    /// The reviewer used a control, the triage list or the graph.
    case user
    /// The host called the review view's API or displayed a new report.
    case host
}

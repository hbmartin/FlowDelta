import AppKit
import FlowDeltaCore
import FlowDeltaLayout
import QuartzCore

/// A key the graph forwards to its delegate once it has handled navigation itself.
@MainActor
@objc(FDFlowGraphKeyCommand)
public enum FlowGraphKeyCommand: Int {
    /// Return or Enter.
    case activate
    /// Space.
    case toggleSlice
    /// Escape.
    case cancel
}

@MainActor
@objc public protocol FlowGraphViewDelegate: AnyObject {
    func flowGraphView(_ view: FlowGraphView, didSelectNodeWithStableID stableID: String)
    /// The context menu for a node. The node is selected before this is asked.
    @objc optional func flowGraphView(_ view: FlowGraphView, menuForNodeWithStableID stableID: String) -> NSMenu?
    /// Handles Return, Space or Escape in the focused graph; false lets the key continue up the responder chain.
    @objc optional func flowGraphView(_ view: FlowGraphView, perform command: FlowGraphKeyCommand) -> Bool
}

@MainActor
@objc(FDFlowGraphView)
public final class FlowGraphView: NSView {
    private let canvasLayer = CALayer()
    private var edgeContainer = CALayer()
    private var nodeViews: [StableID: FlowNodeView] = [:]
    private var currentLayout: GraphLayoutResult?
    private var nodeStates: [StableID: DeltaState] = [:]
    private var edgeStates: [StableID: DeltaState] = [:]
    private var selectedNode: StableID?
    private var emphasizedNodes: Set<StableID>?

    public weak var delegate: (any FlowGraphViewDelegate)?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayerTree()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayerTree()
    }

    override public var isFlipped: Bool {
        true
    }

    public var renderedNodeCount: Int {
        nodeViews.count
    }

    public var renderedStableIDs: [String] {
        nodeViews.keys.map(\.rawValue).sorted()
    }

    public var renderedEdgeCount: Int {
        edgeContainer.sublayers?.count ?? 0
    }

    public func display(
        graph: ControlFlowGraph,
        layout: GraphLayoutResult,
        nodeStates: [StableID: DeltaState] = [:],
        edgeStates: [StableID: DeltaState] = [:],
        animated: Bool = false,
        duration: TimeInterval = 0.6
    ) {
        self.nodeStates = nodeStates
        self.edgeStates = edgeStates
        let previousLayout = currentLayout
        let previousEdges = edgeContainer
        let nextEdges = makeEdgeContainer(graph: graph, layout: layout)
        canvasLayer.insertSublayer(nextEdges, at: 0)
        edgeContainer = nextEdges

        let nextIDs = Set(graph.nodes.map(\.id))
        for node in graph.nodes {
            let nodeView = nodeViews[node.id] ?? makeNodeView(node)
            update(nodeView, for: node, state: nodeStates[node.id])
            if nodeView.superview == nil {
                addSubview(nodeView)
            }
            nodeViews[node.id] = nodeView
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, nodeView) in nodeViews {
            guard let frame = layout.nodeFrames[id] else { continue }
            nodeView.frame = frame
            nodeView.shapeLayer.opacity = 1
            nodeView.shapeLayer.path = CGPath(
                roundedRect: nodeView.bounds,
                cornerWidth: 9,
                cornerHeight: 9,
                transform: nil
            )
            nodeView.updateTextGeometry()
        }
        CATransaction.commit()

        if animated, let previousLayout {
            animateNodes(
                from: previousLayout.nodeFrames,
                to: layout.nodeFrames,
                duration: duration
            )
            animateEdges(from: previousEdges, to: nextEdges, duration: duration)
            let removedIDs = Set(nodeViews.keys).subtracting(nextIDs)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self else { return }
                for id in removedIDs {
                    nodeViews.removeValue(forKey: id)?.removeFromSuperview()
                }
                previousEdges.removeFromSuperlayer()
            }
        } else {
            previousEdges.removeFromSuperlayer()
            for id in Set(nodeViews.keys).subtracting(nextIDs) {
                nodeViews.removeValue(forKey: id)?.removeFromSuperview()
            }
        }

        currentLayout = layout
        canvasLayer.frame = CGRect(origin: .zero, size: layout.contentSize)
        nextEdges.frame = canvasLayer.bounds
        frame.size = layout.contentSize
        needsLayout = true
        updateNodeEmphasis()
    }

    public func hasActiveNodeAnimations() -> Bool {
        nodeViews.values.contains { $0.shapeLayer.animationKeys()?.isEmpty == false }
    }

    public var selectedStableID: String? {
        selectedNode?.rawValue
    }

    public var emphasizedStableIDs: Set<String>? {
        emphasizedNodes.map { Set($0.map(\.rawValue)) }
    }

    /// The context menu the delegate supplies for a node, or nil when it supplies none.
    public func menuForNode(withStableID stableID: String) -> NSMenu? {
        delegate?.flowGraphView?(self, menuForNodeWithStableID: stableID)
    }

    public func selectNode(withStableID stableID: String?) {
        selectedNode = stableID.map(StableID.init(rawValue:))
        updateNodeEmphasis()
        noteFocusRingMaskChanged()
    }

    /// Selects a node as a click or a key would, and tells the delegate.
    private func choose(_ id: StableID) {
        selectedNode = id
        updateNodeEmphasis()
        noteFocusRingMaskChanged()
        delegate?.flowGraphView(self, didSelectNodeWithStableID: id.rawValue)
    }

    public func emphasizeNodes(withStableIDs stableIDs: Set<String>?) {
        emphasizedNodes = stableIDs.map { Set($0.map(StableID.init(rawValue:))) }
        updateNodeEmphasis()
    }

    private func configureLayerTree() {
        wantsLayer = true
        layer = canvasLayer
        canvasLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        canvasLayer.addSublayer(edgeContainer)
    }

    private func makeNodeView(_ node: FlowNode) -> FlowNodeView {
        let nodeView = FlowNodeView(stableID: node.id)
        nodeView.onSelect = { [weak self] id in
            self?.choose(id)
        }
        nodeView.menuProvider = { [weak self] id in
            self?.menuForNode(withStableID: id.rawValue)
        }
        update(nodeView, for: node, state: nodeStates[node.id])
        return nodeView
    }

    private func update(_ nodeView: FlowNodeView, for node: FlowNode, state: DeltaState?) {
        let fill = switch state {
        case .added:
            NSColor(calibratedRed: 0.79, green: 0.91, blue: 0.75, alpha: 1)
        case .removed:
            NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.72, alpha: 1)
        case .modified:
            NSColor(calibratedRed: 0.97, green: 0.88, blue: 0.57, alpha: 1)
        case .affected:
            NSColor(calibratedRed: 0.84, green: 0.78, blue: 0.93, alpha: 1)
        case .retained:
            NSColor(calibratedRed: 0.83, green: 0.89, blue: 0.95, alpha: 1)
        case nil:
            switch node.kind {
            case .entry:
                NSColor(calibratedRed: 0.82, green: 0.91, blue: 0.78, alpha: 1)
            case .exit, .errorExit:
                NSColor(calibratedRed: 0.94, green: 0.82, blue: 0.78, alpha: 1)
            case .condition, .switchCase:
                NSColor(calibratedRed: 0.98, green: 0.91, blue: 0.66, alpha: 1)
            case .deferBlock, .catchBlock:
                NSColor(calibratedRed: 0.86, green: 0.82, blue: 0.94, alpha: 1)
            case .basicBlock:
                NSColor(calibratedRed: 0.83, green: 0.89, blue: 0.95, alpha: 1)
            }
        }
        nodeView.shapeLayer.fillColor = fill.cgColor
        nodeView.shapeLayer.strokeColor = NSColor(calibratedWhite: 0.35, alpha: 0.8).cgColor
        nodeView.labelLayer.string = node.label
        nodeView.setAccessibilityLabel(node.label.replacingOccurrences(of: "\n", with: ", "))
        nodeView.setAccessibilityHelp(state.map { "Flow node state: \($0.rawValue)" } ?? "Control-flow node")
    }

    private func makeEdgeContainer(graph: ControlFlowGraph, layout: GraphLayoutResult) -> CALayer {
        let container = CALayer()
        for edge in graph.edges {
            guard let route = layout.edgeRoutes[edge.id], let first = route.points.first else { continue }
            let path = CGMutablePath()
            path.move(to: first)
            for point in route.points.dropFirst() {
                path.addLine(to: point)
            }
            let layer = CAShapeLayer()
            layer.name = "edge:\(edge.id.rawValue)"
            layer.path = path
            layer.fillColor = nil
            let state = edgeStates[edge.id]
            if edge.kind == .dataDependency {
                layer.lineDashPattern = [2, 3]
            }
            switch state {
            case .added:
                layer.strokeColor = NSColor.systemGreen.cgColor
            case .removed:
                layer.strokeColor = NSColor.systemRed.cgColor
                layer.lineDashPattern = [5, 3]
            case .modified:
                layer.strokeColor = NSColor.systemOrange.cgColor
            case .affected:
                layer.strokeColor = NSColor.systemPurple.cgColor
            case .retained, nil:
                layer.strokeColor = edge.kind == .dataDependency
                    ? NSColor.systemTeal.cgColor
                    : route.isBackEdge
                    ? NSColor.systemOrange.cgColor
                    : NSColor(calibratedWhite: 0.35, alpha: 0.75).cgColor
            }
            layer.lineWidth = route.isBackEdge ? 2 : 1.5
            layer.lineJoin = .round
            layer.lineCap = .round
            container.addSublayer(layer)
        }
        return container
    }

    private func animateNodes(
        from oldFrames: [StableID: CGRect],
        to newFrames: [StableID: CGRect],
        duration: TimeInterval
    ) {
        let transition = StagedLayoutTransition(oldFrames: oldFrames, newFrames: newFrames)
        let progresses: [CGFloat] = [0, 0.25, 0.75, 1]
        for (id, nodeView) in nodeViews {
            let states = progresses.compactMap { progress in
                transition.states(at: progress).first { $0.id == id }
            }
            guard states.count == progresses.count else { continue }
            let position = CAKeyframeAnimation(keyPath: "position")
            position.keyTimes = [0, 0.25, 0.75, 1]
            position.values = states.map { NSValue(point: $0.frame.center) }
            let bounds = CAKeyframeAnimation(keyPath: "bounds")
            bounds.keyTimes = position.keyTimes
            bounds.values = states.map { NSValue(rect: CGRect(origin: .zero, size: $0.frame.size)) }
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.keyTimes = position.keyTimes
            opacity.values = states.map(\.opacity)
            let group = CAAnimationGroup()
            group.animations = [position, bounds, opacity]
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            nodeView.shapeLayer.add(group, forKey: "flowdelta.stagedTransition")
        }
    }

    private func animateEdges(from old: CALayer, to new: CALayer, duration: TimeInterval) {
        let fadeOut = CAKeyframeAnimation(keyPath: "opacity")
        fadeOut.keyTimes = [0, 0.25, 1]
        fadeOut.values = [1, 0, 0]
        fadeOut.duration = duration
        old.add(fadeOut, forKey: "flowdelta.fadeRemovedEdges")

        let fadeIn = CAKeyframeAnimation(keyPath: "opacity")
        fadeIn.keyTimes = [0, 0.75, 1]
        fadeIn.values = [0, 0, 1]
        fadeIn.duration = duration
        new.add(fadeIn, forKey: "flowdelta.revealAddedEdges")
    }

    private func updateNodeEmphasis() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, nodeView) in nodeViews {
            let layer = nodeView.shapeLayer
            let isSelected = id == selectedNode
            layer.lineWidth = isSelected ? 3 : 1
            layer.strokeColor = isSelected
                ? NSColor.keyboardFocusIndicatorColor.cgColor
                : NSColor(calibratedWhite: 0.35, alpha: 0.8).cgColor
            layer.opacity = emphasizedNodes.map { $0.contains(id) ? 1 : 0.20 } ?? 1
        }
        CATransaction.commit()
    }
}

@MainActor
private final class FlowNodeView: NSView {
    let stableID: StableID
    let shapeLayer = CAShapeLayer()
    let labelLayer = CATextLayer()
    var onSelect: ((StableID) -> Void)?
    var menuProvider: ((StableID) -> NSMenu?)?

    init(stableID: StableID) {
        self.stableID = stableID
        super.init(frame: .zero)
        wantsLayer = true
        layer = shapeLayer
        shapeLayer.name = "node:\(stableID.rawValue)"
        shapeLayer.lineWidth = 1
        shapeLayer.shadowColor = NSColor.black.cgColor
        shapeLayer.shadowOpacity = 0.16
        shapeLayer.shadowRadius = 3
        shapeLayer.shadowOffset = CGSize(width: 0, height: 1)
        labelLayer.name = "label"
        labelLayer.alignmentMode = .center
        labelLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        labelLayer.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        labelLayer.fontSize = 12
        labelLayer.foregroundColor = NSColor.labelColor.cgColor
        labelLayer.isWrapped = true
        shapeLayer.addSublayer(labelLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier(stableID.rawValue)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        shapeLayer.path = CGPath(
            roundedRect: bounds,
            cornerWidth: 9,
            cornerHeight: 9,
            transform: nil
        )
        updateTextGeometry()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(stableID)
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?(stableID)
        return true
    }

    /// Like Finder, a secondary click selects the node before showing its menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        onSelect?(stableID)
        return menuProvider?(stableID)
    }

    override func accessibilityPerformShowMenu() -> Bool {
        onSelect?(stableID)
        guard let menu = menuProvider?(stableID) else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
        return true
    }

    func updateTextGeometry() {
        labelLayer.frame = bounds.insetBy(dx: 9, dy: 9)
    }
}

// MARK: Keyboard

public extension FlowGraphView {
    /// Moves the selection as an arrow, Home or End key would, scrolling the new node into view.
    func moveSelection(_ move: GraphNavigationMove) {
        guard let currentLayout,
              let target = GraphNavigator(layout: currentLayout).target(from: selectedNode, move: move)
        else { return }
        if target != selectedNode {
            choose(target)
        }
        if let frame = currentLayout.nodeFrames[target] {
            scrollToVisible(frame.insetBy(dx: -24, dy: -24))
        }
        if let nodeView = nodeViews[target] {
            NSAccessibility.post(element: nodeView, notification: .focusedUIElementChanged)
        }
    }
}

public extension FlowGraphView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override var canBecomeKeyView: Bool {
        !nodeViews.isEmpty
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if selectedNode == nil {
            moveSelection(.first)
        }
        noteFocusRingMaskChanged()
        return true
    }

    override func resignFirstResponder() -> Bool {
        noteFocusRingMaskChanged()
        return super.resignFirstResponder()
    }

    /// The focus ring surrounds the selected node, like a focused icon in Finder.
    override var focusRingMaskBounds: NSRect {
        selectedNode.flatMap { currentLayout?.nodeFrames[$0] } ?? bounds
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 9, yRadius: 9).fill()
    }

    override func keyDown(with event: NSEvent) {
        if let move = Self.move(for: event) {
            moveSelection(move)
        } else if let command = Self.command(for: event), delegate?.flowGraphView?(self, perform: command) == true {
            return
        } else {
            super.keyDown(with: event)
        }
    }

    internal static func move(for event: NSEvent) -> GraphNavigationMove? {
        switch event.specialKey {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        case .home: .first
        case .end: .last
        default: nil
        }
    }

    internal static func command(for event: NSEvent) -> FlowGraphKeyCommand? {
        switch event.specialKey {
        case .carriageReturn, .enter, .newline: return .activate
        default: break
        }
        switch event.charactersIgnoringModifiers {
        case " ": return .toggleSlice
        case "\u{1b}": return .cancel
        default: return nil
        }
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

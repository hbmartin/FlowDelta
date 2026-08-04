import AppKit
import FlowDeltaCore
import FlowDeltaLayout
import QuartzCore

@MainActor
@objc(FDFlowGraphView)
public final class FlowGraphView: NSView {
    private let canvasLayer = CALayer()
    private let nodeContainer = CALayer()
    private var edgeContainer = CALayer()
    private var nodeLayers: [StableID: CAShapeLayer] = [:]
    private var currentLayout: GraphLayoutResult?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayerTree()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayerTree()
    }

    public override var isFlipped: Bool { true }

    public var renderedNodeCount: Int { nodeLayers.count }
    public var renderedEdgeCount: Int { edgeContainer.sublayers?.count ?? 0 }

    public func display(
        graph: ControlFlowGraph,
        layout: GraphLayoutResult,
        animated: Bool = false,
        duration: TimeInterval = 0.6
    ) {
        let previousLayout = currentLayout
        let previousEdges = edgeContainer
        let nextEdges = makeEdgeContainer(graph: graph, layout: layout)
        canvasLayer.insertSublayer(nextEdges, below: nodeContainer)
        edgeContainer = nextEdges

        let nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let nextIDs = Set(nodesByID.keys)
        for node in graph.nodes {
            let layer = nodeLayers[node.id] ?? makeNodeLayer(node)
            update(layer, for: node)
            if layer.superlayer == nil {
                nodeContainer.addSublayer(layer)
            }
            nodeLayers[node.id] = layer
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, layer) in nodeLayers {
            guard let frame = layout.nodeFrames[id] else { continue }
            layer.frame = frame
            layer.opacity = 1
            layer.path = CGPath(
                roundedRect: layer.bounds,
                cornerWidth: 9,
                cornerHeight: 9,
                transform: nil
            )
            updateTextGeometry(in: layer)
        }
        CATransaction.commit()

        if animated, let previousLayout {
            animateNodes(
                from: previousLayout.nodeFrames,
                to: layout.nodeFrames,
                duration: duration
            )
            animateEdges(from: previousEdges, to: nextEdges, duration: duration)
            let removedIDs = Set(nodeLayers.keys).subtracting(nextIDs)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self else { return }
                for id in removedIDs {
                    self.nodeLayers.removeValue(forKey: id)?.removeFromSuperlayer()
                }
                previousEdges.removeFromSuperlayer()
            }
        } else {
            previousEdges.removeFromSuperlayer()
            for id in Set(nodeLayers.keys).subtracting(nextIDs) {
                nodeLayers.removeValue(forKey: id)?.removeFromSuperlayer()
            }
        }

        currentLayout = layout
        canvasLayer.frame = CGRect(origin: .zero, size: layout.contentSize)
        nodeContainer.frame = canvasLayer.bounds
        nextEdges.frame = canvasLayer.bounds
        frame.size = layout.contentSize
        needsLayout = true
    }

    public func hasActiveNodeAnimations() -> Bool {
        nodeLayers.values.contains { $0.animationKeys()?.isEmpty == false }
    }

    private func configureLayerTree() {
        wantsLayer = true
        layer = canvasLayer
        canvasLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        canvasLayer.addSublayer(edgeContainer)
        canvasLayer.addSublayer(nodeContainer)
    }

    private func makeNodeLayer(_ node: FlowNode) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.name = "node:\(node.id.rawValue)"
        layer.lineWidth = 1
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)

        let text = CATextLayer()
        text.name = "label"
        text.alignmentMode = .center
        text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        text.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        text.fontSize = 12
        text.foregroundColor = NSColor.labelColor.cgColor
        text.isWrapped = true
        layer.addSublayer(text)
        update(layer, for: node)
        return layer
    }

    private func update(_ layer: CAShapeLayer, for node: FlowNode) {
        let fill: NSColor
        switch node.kind {
        case .entry:
            fill = NSColor(calibratedRed: 0.82, green: 0.91, blue: 0.78, alpha: 1)
        case .exit, .errorExit:
            fill = NSColor(calibratedRed: 0.94, green: 0.82, blue: 0.78, alpha: 1)
        case .condition, .switchCase:
            fill = NSColor(calibratedRed: 0.98, green: 0.91, blue: 0.66, alpha: 1)
        case .deferBlock, .catchBlock:
            fill = NSColor(calibratedRed: 0.86, green: 0.82, blue: 0.94, alpha: 1)
        case .basicBlock:
            fill = NSColor(calibratedRed: 0.83, green: 0.89, blue: 0.95, alpha: 1)
        }
        layer.fillColor = fill.cgColor
        layer.strokeColor = NSColor(calibratedWhite: 0.35, alpha: 0.8).cgColor
        (layer.sublayers?.first { $0.name == "label" } as? CATextLayer)?.string = node.label
    }

    private func updateTextGeometry(in layer: CAShapeLayer) {
        guard let text = layer.sublayers?.first(where: { $0.name == "label" }) else { return }
        text.frame = layer.bounds.insetBy(dx: 9, dy: 9)
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
            layer.strokeColor = route.isBackEdge
                ? NSColor.systemOrange.cgColor
                : NSColor(calibratedWhite: 0.35, alpha: 0.75).cgColor
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
        for (id, layer) in nodeLayers {
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
            layer.add(group, forKey: "flowdelta.stagedTransition")
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
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

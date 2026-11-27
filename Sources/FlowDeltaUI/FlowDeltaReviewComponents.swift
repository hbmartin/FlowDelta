import AppKit
import FlowDeltaCore

typealias ReviewRow = FlowTriageEntry

/// A triage list row: a concern group heading or an entity change.
enum TriageRow {
    case group(title: String, kind: FlowConcernKind?)
    case entity(ReviewRow)

    var entity: ReviewRow? {
        if case let .entity(row) = self {
            row
        } else {
            nil
        }
    }

    /// The heading a group row shows: its title without code quotes, then its kind.
    static func heading(title: String, kind: FlowConcernKind?) -> String {
        let plain = title.replacingOccurrences(of: "`", with: "")
        guard let kind else { return plain }
        return "\(plain) · \(kind.rawValue.capitalized)"
    }
}

extension FlowChangeClassification {
    var reviewLabel: String {
        switch self {
        case .guardInserted: "guard inserted"
        case .conditionChanged: "condition changed"
        case .earlyReturnAdded: "early return added"
        case .branchAdded: "branch added"
        case .branchRemoved: "branch removed"
        case .loopChanged: "loop changed"
        case .errorPathAdded: "error path added"
        }
    }
}

@MainActor
enum ReviewViewComponents {
    static func short(_ revision: String) -> String {
        String(revision.prefix(8))
    }

    static func color(for kind: EntityChangeKind) -> NSColor {
        switch kind {
        case .added: .systemGreen
        case .removed: .systemRed
        case .modified: .systemOrange
        case .moved, .renamed: .systemPurple
        case .unchanged: .secondaryLabelColor
        }
    }

    static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingTail
        cell.textField = field
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    /// A concern group heading, drawn as a source-list section header.
    static func makeGroupCell(heading: String, row: Int) -> NSTableCellView {
        let cell = makeCell(identifier: NSUserInterfaceItemIdentifier("group"))
        cell.textField?.stringValue = heading.uppercased()
        cell.textField?.toolTip = heading
        cell.textField?.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        cell.textField?.textColor = .secondaryLabelColor
        cell.setAccessibilityLabel(heading)
        cell.setAccessibilityIdentifier("FlowDelta.Review.TriageGroup.\(row)")
        return cell
    }

    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// A small control for the review's accessory bars.
    static func configureBarButton(_ button: NSButton, target: AnyObject, action: Selector) {
        button.bezelStyle = .recessed
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.target = target
        button.action = action
    }

    static func makeLegend() -> NSStackView {
        let stack = NSStackView(views: [
            LegendItem(title: "Added", color: NSColor(calibratedRed: 0.42, green: 0.68, blue: 0.35, alpha: 1)),
            LegendItem(title: "Removed", color: NSColor(calibratedRed: 0.76, green: 0.32, blue: 0.27, alpha: 1)),
            LegendItem(title: "Modified", color: NSColor(calibratedRed: 0.80, green: 0.62, blue: 0.17, alpha: 1)),
            LegendItem(title: "Affected", color: NSColor(calibratedRed: 0.46, green: 0.33, blue: 0.63, alpha: 1))
        ])
        stack.orientation = .horizontal
        stack.spacing = 10
        return stack
    }
}

@MainActor
final class SnowLeopardHeaderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let colors = [
            NSColor(calibratedWhite: 0.96, alpha: 1),
            NSColor(calibratedWhite: 0.79, alpha: 1)
        ]
        NSGradient(colors: colors)?.draw(in: bounds, angle: -90)
        NSColor(calibratedWhite: 0.62, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1)).fill()
    }
}

/// A slim bar under the header for a notice or the walkthrough, in the manner of a Snow Leopard info bar.
@MainActor
final class ReviewInfoBar: NSView {
    let messageLabel = NSTextField(labelWithString: "")
    let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    /// Lays out the bar's controls, with the message between the leading and trailing ones.
    func setViews(leading: [NSView], trailing: [NSView]) {
        stack.setViews(leading + [messageLabel], in: .leading)
        stack.setViews(trailing, in: .trailing)
    }

    override func draw(_ dirtyRect: NSRect) {
        let colors = [
            NSColor(calibratedRed: 1.00, green: 0.97, blue: 0.82, alpha: 1),
            NSColor(calibratedRed: 0.96, green: 0.90, blue: 0.66, alpha: 1)
        ]
        NSGradient(colors: colors)?.draw(in: bounds, angle: -90)
        NSColor(calibratedRed: 0.72, green: 0.64, blue: 0.40, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1)).fill()
    }
}

@MainActor
private final class LegendItem: NSView {
    init(title: String, color: NSColor) {
        super.init(frame: .zero)
        let swatch = NSView()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = color.cgColor
        swatch.layer?.cornerRadius = 4
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        addSubview(swatch)
        addSubview(label)
        NSLayoutConstraint.activate([
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor),
            swatch.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 8),
            swatch.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

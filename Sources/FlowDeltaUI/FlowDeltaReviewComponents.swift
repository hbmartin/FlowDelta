import AppKit
import FlowDeltaCore

struct ReviewRow {
    let file: FileFlowDelta
    let change: EntityChange
    let function: FunctionFlowDelta?
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

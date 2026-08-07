import AppKit
import FlowDeltaCore
import Foundation
import HighlightKit

@MainActor
@objc(FDFlowSourceView)
public final class FlowSourceView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Source")
    private let scrollView = NSScrollView()
    public let textView = NSTextView()
    private var snapshot: SourceSnapshot?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    public func display(_ snapshot: SourceSnapshot?, title: String) {
        self.snapshot = snapshot
        titleLabel.stringValue = title
        guard let snapshot else {
            textView.string = "Source unavailable"
            return
        }
        let highlighted = try? Highlighter.shared.attributedString(
            for: snapshot.text,
            selection: .named("swift"),
            theme: .xcodeLight
        )
        textView.textStorage?.setAttributedString(
            highlighted ?? NSAttributedString(
                string: snapshot.text,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
            )
        )
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    public func select(_ range: SourceRange?) {
        guard let range, let snapshot else { return }
        let maximum = snapshot.text.utf16.count
        let location = min(maximum, max(0, range.start.utf16Offset))
        let length = min(maximum - location, max(0, range.end.utf16Offset - location))
        let selection = NSRange(location: location, length: length)
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
        window?.makeFirstResponder(textView)
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1).cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

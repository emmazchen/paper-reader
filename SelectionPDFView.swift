import AppKit
import PDFKit

// PDFKit link actions must not navigate a pane during a selection gesture.
// The reader handles deliberate link clicks after mouse-up instead.
final class SelectionPDFView: PDFView {
    var suppressLinkActions = false
    var interactionBegan: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        interactionBegan?()
        let previous = suppressLinkActions
        suppressLinkActions = true
        defer { suppressLinkActions = previous }
        super.mouseDown(with:event)
    }
    override func perform(_ action: PDFAction) {
        guard !suppressLinkActions else { return }
        super.perform(action)
    }
    override func scrollWheel(with event: NSEvent) {
        interactionBegan?()
        super.scrollWheel(with:event)
    }
}

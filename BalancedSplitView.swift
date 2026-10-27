import AppKit

private final class ReaderDivider: NSView {
    var move: ((CGFloat) -> Void)?
    override func resetCursorRects() { addCursorRect(bounds,cursor:.resizeLeftRight) }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { move?(0.5) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let parent = superview, parent.bounds.width > 0 else { return }
        move?(parent.convert(event.locationInWindow,from:nil).x/parent.bounds.width)
    }
}

// Own the pane widths with required Auto Layout constraints. NSSplitView's
// automatic pane sizing no longer competes with the initial equal split.
final class BalancedSplitView: NSView {
    private let left: NSView
    private var proportion: NSLayoutConstraint!
    private let dividerWidth: CGFloat = 6

    init(left: NSView, right: NSView) {
        self.left = left
        super.init(frame:.zero)
        let divider = ReaderDivider()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        for view in [left,divider,right] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.topAnchor.constraint(equalTo:topAnchor).isActive = true
            view.bottomAnchor.constraint(equalTo:bottomAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo:leadingAnchor),
            divider.leadingAnchor.constraint(equalTo:left.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant:dividerWidth),
            right.leadingAnchor.constraint(equalTo:divider.trailingAnchor),
            right.trailingAnchor.constraint(equalTo:trailingAnchor)
        ])
        setFraction(0.5)
        divider.move = { [weak self] fraction in self?.setFraction(fraction) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setFraction(_ fraction: CGFloat) {
        let fraction = min(0.85,max(0.15,fraction))
        proportion?.isActive = false
        proportion = left.widthAnchor.constraint(equalTo:widthAnchor,multiplier:fraction,constant:-dividerWidth*fraction)
        proportion.isActive = true
    }
}

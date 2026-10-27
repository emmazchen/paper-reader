import AppKit
let left = NSView(), right = NSView()
let split = BalancedSplitView(left:left,right:right)
for width in [900.0,1250.0,1800.0] {
    split.frame = NSRect(x:0,y:0,width:width,height:750)
    split.layoutSubtreeIfNeeded()
    precondition(abs(left.frame.width-right.frame.width) < 0.5,"Pane widths must be equal at \(width): \(left.frame.width), \(right.frame.width)")
}
split.setFraction(0.4); split.layoutSubtreeIfNeeded()
precondition(abs(left.frame.width/(split.bounds.width-6)-0.4) < 0.001,"Manual proportion")
print("4 pane layout checks passed")

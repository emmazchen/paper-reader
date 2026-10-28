import AppKit
import PDFKit
import CoreText

var checkCount = 0
func check(_ value: Bool, _ message: String) { precondition(value,message); checkCount += 1 }
let data = NSMutableData()
var box = CGRect(x:0,y:0,width:612,height:792)
let context = CGContext(consumer:CGDataConsumer(data:data as CFMutableData)!,mediaBox:&box,nil)!
for text in ["See Fig. 2 for the search target.","Ordinary text to select on second page.","Figure 2. Caption for the example figure."] {
    context.beginPDFPage(nil); context.textPosition = CGPoint(x:50,y:700)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,14,nil)])),context)
    context.endPDFPage()
}
context.closePDF()
let reader = Reader()
reader.previousMentionButton = NSButton(); reader.nextMentionButton = NSButton()
reader.document = PDFDocument(data:data as Data)!
reader.pdf.document = reader.document
reader.pdf.frame = NSRect(x:-700,y:0,width:600,height:700)
reader.textPDF.frame = NSRect(x:0,y:0,width:600,height:700)
reader.textPDF.document = PDFDocument(data:data as Data)!
reader.textQuery.stringValue = "target"
let second = reader.textPDF.document!.page(at:1)!
func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)!
}
func drain() { RunLoop.main.run(until:Date().addingTimeInterval(0.35)) }

// The actual queued Reader search used to clear this selection and jump.
reader.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:reader.textQuery))
let staleSearch = reader.pendingSearch!
reader.textPDF.go(to:second)
_ = reader.handlePDFInteraction(event(.leftMouseDown,NSPoint(x:20,y:20)))
reader.textPDF.setCurrentSelection(second.selection(for:NSRange(location:0,length:13)),animate:false)
drain()
check(reader.textPDF.currentPage === second,"Selection cancels pending jump in normal mode")
check(reader.textPDF.currentSelection?.string == "Ordinary text","Pending search preserves selection")
// Exercise the callback even if dispatch had already retained it.
staleSearch.perform()
check(reader.textPDF.currentPage === second,"Stale generation cannot navigate")
_ = reader.handlePDFInteraction(event(.leftMouseDragged,NSPoint(x:80,y:20)))
_ = reader.handlePDFInteraction(event(.leftMouseUp,NSPoint(x:80,y:20))); drain()

// Explicit search is still allowed to navigate after interacting with the PDF.
reader.findText()
let first = reader.textPDF.document!.page(at:0)!
check(reader.textPDF.currentPage === first,"Explicit Find still navigates")
reader.textPDF.go(to:second)
reader.textQuery.stringValue = "target"
reader.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:reader.textQuery))
let scrollCG = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:1,wheel2:0,wheel3:0)!
scrollCG.location = CGPoint(x:20,y:20)
reader.textPDF.interactionBegan = { reader.cancelPendingSearch() }
reader.textPDF.scrollWheel(with:NSEvent(cgEvent:scrollCG)!)
drain()
check(reader.textPDF.currentPage === second,"Scrolling cancels pending search")

// Linked references must not navigate until a deliberate click completes.
reader.textPDF.go(to:first)
reader.pdf.go(to:reader.document!.page(at:0)!)
let reference = first.selection(for:FigureSearch.references(first.string!)[0].range)!
let bounds = reference.bounds(for:first)
let point = reader.textPDF.convert(NSPoint(x:bounds.midX,y:bounds.midY),from:first)
let mousePoint = reader.textPDF.convert(point,to:nil)
let action = PDFActionGoTo(destination:PDFDestination(page:second,at:NSPoint(x:0,y:700)))
_ = reader.handlePDFInteraction(event(.leftMouseDown,mousePoint))
reader.textPDF.perform(action)
check(reader.textPDF.currentPage === first,"Native links suppressed on mouse-down")
_ = reader.handlePDFInteraction(event(.leftMouseDragged,NSPoint(x:mousePoint.x+25,y:mousePoint.y)))
_ = reader.handlePDFInteraction(event(.leftMouseUp,NSPoint(x:mousePoint.x+25,y:mousePoint.y))); drain()
check(reader.pdf.currentPage === reader.document!.page(at:0)!,"Dragging across reference does not navigate left")
check(reader.textPDF.currentPage === first,"Dragging across reference does not navigate right")
_ = reader.handlePDFInteraction(event(.leftMouseDown,mousePoint))
check(reader.pdf.currentPage === reader.document!.page(at:0)!,"Click waits for mouse-up")
_ = reader.handlePDFInteraction(event(.leftMouseUp,mousePoint)); drain()
check(reader.pdf.currentPage === reader.document!.page(at:2)!,"Intentional figure click navigates left")
check(reader.textPDF.currentPage === first,"Intentional figure click preserves right page")

reader.annotationTool = .highlight
_ = reader.handlePDFInteraction(event(.leftMouseDown,mousePoint))
reader.textPDF.perform(action)
check(reader.textPDF.currentPage === first,"Native links suppressed in highlighting mode")
_ = reader.handlePDFInteraction(event(.leftMouseDragged,NSPoint(x:mousePoint.x+25,y:mousePoint.y)))
_ = reader.handlePDFInteraction(event(.leftMouseUp,NSPoint(x:mousePoint.x+25,y:mousePoint.y))); drain()
check(reader.textPDF.currentPage === first,"Highlight gesture preserves right page")
// Applying and saving a real highlight must not change either PDF position.
reader.annotationTool = .none
reader.highlightStore = HighlightStore(left:reader.document!,right:reader.textPDF.document!)
reader.lastPDF = reader.textPDF
reader.textPDF.go(to:second)
reader.textPDF.setCurrentSelection(second.selection(for:NSRange(location:0,length:13)),animate:false)
let leftBefore = reader.pdf.currentPage
reader.applySelectedHighlight()
check(reader.textPDF.currentPage === second && reader.pdf.currentPage === leftBefore,"Applying highlight preserves both pane positions")
let saveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf")
defer { try? FileManager.default.removeItem(at:saveURL) }
try reader.highlightStore!.save(to:saveURL)
check(reader.textPDF.currentPage === second && reader.pdf.currentPage === leftBefore,"Saving highlight preserves both pane positions")
reader.textQuery.stringValue = "the"
reader.findText(); reader.nextMention()
check(reader.textPDF.currentPage === reader.textPDF.document!.page(at:2)!,"Shared Next navigates text matches")
reader.previousMention()
check(reader.textPDF.currentPage === first,"Shared Previous navigates text matches")
reader.number.stringValue = "2"
reader.findPassages(); reader.nextMention()
check(reader.textPDF.currentPage === reader.textPDF.document!.page(at:2)!,"Shared Next navigates figure matches")
reader.previousMention()
check(reader.textPDF.currentPage === first,"Shared Previous navigates figure matches")
print("\(checkCount) PDF interaction checks passed")

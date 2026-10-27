import AppKit
import PDFKit
import CoreText
setbuf(stdout,nil)
func check(_ value: Bool,_ message: String) { precondition(value,message) }
let data = NSMutableData()
var box = CGRect(x:0,y:0,width:612,height:792)
let context = CGContext(consumer:CGDataConsumer(data:data as CFMutableData)!,mediaBox:&box,nil)!
for _ in 0..<2 {
    context.beginPDFPage(nil)
    for (text,y) in [("First line of selected text.",700.0),("Second line of selected text.",680.0)] {
        context.textPosition = CGPoint(x:50,y:y)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,12,nil)])),context)
    }
    context.endPDFPage()
}
context.closePDF()
let left = PDFDocument(data:data as Data)!, right = PDFDocument(data:data as Data)!
let store = HighlightStore(left:left,right:right)
store.undoManager.groupsByEvent = false
let source = right.page(at:0)!
let selection = source.selection(for:NSRange(location:0,length:(source.string! as NSString).length))!
store.undoManager.beginUndoGrouping()
let count = store.highlight(selection,color:NSColor.systemYellow.withAlphaComponent(0.4))
store.undoManager.endUndoGrouping()
check(count == 2,"Create one highlight per line")
check(left.page(at:0)!.annotations.count == 2 && right.page(at:0)!.annotations.count == 2,"Both views contain highlights")
check(store.isDirty,"New highlights mark document dirty")
check(left.page(at:1)!.annotations.isEmpty,"Do not annotate unrelated pages")
check(left.page(at:0)!.annotations[0].quadrilateralPoints?.count == 4,"Use text highlight geometry")
let saved = left.dataRepresentation()!
let reloaded = PDFDocument(data:saved)!
check(reloaded.page(at:0)!.annotations.count == 2,"Highlights survive saving and reopening")
check(HighlightStore.isHighlight(reloaded.page(at:0)!.annotations[0]),"Saved highlight is a PDF annotation")
store.markSaved(); check(!store.isDirty,"Save clears dirty state")
store.undoManager.undo()
check(left.page(at:0)!.annotations.isEmpty && right.page(at:0)!.annotations.isEmpty,"Undo synchronizes both documents")
check(store.isDirty,"Undo after save is unsaved")
store.undoManager.redo()
check(left.page(at:0)!.annotations.count == 2 && !store.isDirty,"Redo returns to saved state")
store.undoManager.beginUndoGrouping()
check(store.remove(page:right.page(at:0)!,annotation:right.page(at:0)!.annotations[0]),"Remove clicked highlight")
store.undoManager.endUndoGrouping()
check(left.page(at:0)!.annotations.count == 1 && right.page(at:0)!.annotations.count == 1,"Removal synchronized")
store.undoManager.undo()
check(left.page(at:0)!.annotations.count == 2 && !store.isDirty,"Undo removal")
let loadedStore = HighlightStore(left:PDFDocument(data:saved)!,right:PDFDocument(data:saved)!)
let loadedPage = loadedStore.right.page(at:0)!
_ = loadedStore.remove(page:loadedPage,annotation:loadedPage.annotations[0])
check(loadedStore.left.page(at:0)!.annotations.count == 1,"Remove reloaded highlight in both documents")
print("15 highlight checks passed")

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:directory) }
let file = directory.appendingPathComponent("paper.pdf")
try (data as Data).write(to:file)
try loadedStore.save(to:file)
check(PDFDocument(url:file)!.page(at:0)!.annotations.count == 1,"Save highlights to the opened PDF path")
check(!loadedStore.isDirty,"Successful autosave clears unsaved state")
check(PDFDocument(url:file)!.pageCount == 2,"Autosave retains every PDF page")
let failureStore = HighlightStore(left:PDFDocument(data:data as Data)!,right:PDFDocument(data:data as Data)!)
let failurePage = failureStore.left.page(at:0)!
let failureSelection = failurePage.selection(for:NSRange(location:0,length:10))!
_ = failureStore.highlight(failureSelection,color:.yellow)
do {
    try failureStore.save(to:directory.appendingPathComponent("missing/paper.pdf"))
    preconditionFailure("Writing to missing parent must fail")
} catch { check(failureStore.isDirty,"Failed autosave retains unsaved changes") }
print("4 autosave checks passed")

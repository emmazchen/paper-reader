import AppKit
import PDFKit

final class HighlightStore {
    static func isHighlight(_ annotation: PDFAnnotation) -> Bool {
        annotation.type?.trimmingCharacters(in:CharacterSet(charactersIn:"/")) == "Highlight"
    }
    struct Entry { let page: PDFPage; let annotation: PDFAnnotation }
    let left: PDFDocument
    let right: PDFDocument
    let undoManager = UndoManager()
    private var state = UUID()
    private var savedState: UUID
    var didChange: (() -> Void)?
    var isDirty: Bool { state != savedState }

    init(left: PDFDocument, right: PDFDocument) {
        self.left = left; self.right = right; savedState = state
    }
    func save(to url: URL) throws {
        guard let data = left.dataRepresentation() else {
            throw NSError(domain:"PaperReader",code:1,userInfo:[NSLocalizedDescriptionKey:"Could not encode the annotated PDF."])
        }
        // Encode first, then replace atomically; a failed write leaves the
        // previous file intact and keeps the unsaved state in memory.
        try data.write(to:url.resolvingSymlinksInPath(),options:.atomic)
        markSaved()
    }
    func markSaved() { savedState = state; didChange?() }

    private func perform(add: [Entry], remove: [Entry], nextState: UUID, name: String) {
        let oldState = state
        for entry in remove { entry.page.removeAnnotation(entry.annotation) }
        for entry in add { entry.page.addAnnotation(entry.annotation) }
        state = nextState
        undoManager.registerUndo(withTarget:self) { store in
            store.perform(add:remove,remove:add,nextState:oldState,name:name)
        }
        undoManager.setActionName(name)
        didChange?()
    }
    @discardableResult func highlight(_ selection: PDFSelection, color: NSColor) -> Int {
        var entries: [Entry] = []
        for line in selection.selectionsByLine() {
            for sourcePage in line.pages {
                guard let source = sourcePage.document else { continue }
                let index = source.index(for:sourcePage)
                let bounds = line.bounds(for:sourcePage)
                guard !bounds.isEmpty, index != NSNotFound else { continue }
                let id = UUID().uuidString
                for document in [left,right] {
                    guard let page = document.page(at:index) else { continue }
                    let annotation = PDFAnnotation(bounds:bounds,forType:.highlight,withProperties:nil)
                    annotation.color = color
                    annotation.contents = line.string
                    annotation.setValue(id,forAnnotationKey:PDFAnnotationKey(rawValue:"NM"))
                    annotation.quadrilateralPoints = [
                        NSValue(point:NSPoint(x:0,y:bounds.height)),
                        NSValue(point:NSPoint(x:bounds.width,y:bounds.height)),
                        NSValue(point:.zero),
                        NSValue(point:NSPoint(x:bounds.width,y:0))
                    ]
                    entries.append(Entry(page:page,annotation:annotation))
                }
            }
        }
        guard !entries.isEmpty else { return 0 }
        perform(add:entries,remove:[],nextState:UUID(),name:"Highlight Text")
        return entries.count/2
    }
    @discardableResult func remove(page sourcePage: PDFPage, annotation: PDFAnnotation) -> Bool {
        guard Self.isHighlight(annotation),
              let source = sourcePage.document else { return false }
        let index = source.index(for:sourcePage)
        let id = annotation.value(forAnnotationKey:PDFAnnotationKey(rawValue:"NM")) as? String
        var entries: [Entry] = []
        for document in [left,right] {
            guard let page = document.page(at:index) else { continue }
            let twin = page.annotations.first { candidate in
                if candidate === annotation { return true }
                if let id { return candidate.value(forAnnotationKey:PDFAnnotationKey(rawValue:"NM")) as? String == id }
                return candidate.type == annotation.type && candidate.bounds == annotation.bounds && candidate.contents == annotation.contents
            }
            if let twin { entries.append(Entry(page:page,annotation:twin)) }
        }
        guard !entries.isEmpty else { return false }
        perform(add:[],remove:entries,nextState:UUID(),name:"Remove Highlight")
        return true
    }
}

import AppKit
import PDFKit

final class AnnotationToolButton: NSButton {
    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        // Use the same lighter treatment for a held click and a latched tool.
        let active = state == .on || cell?.isHighlighted == true
        guard active else {
            super.draw(dirtyRect)
            return
        }
        let dark = effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        if !dark, let cell {
            // Let AppKit render the same pressed treatment as the Find button
            // rather than imposing the dark-mode highlight color in light mode.
            let savedState = cell.state
            let savedHighlight = cell.isHighlighted
            cell.state = .off
            cell.isHighlighted = true
            super.draw(dirtyRect)
            cell.state = savedState
            cell.isHighlighted = savedHighlight
            return
        }
        let shape = NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:2),xRadius:5,yRadius:5)
        let fill = NSColor(srgbRed:0.83,green:0.86,blue:0.90,alpha:1)
        fill.setFill(); shape.fill()
        NSColor.separatorColor.setStroke(); shape.stroke()
        let attributes: [NSAttributedString.Key:Any] = [
            .font:font ?? NSFont.systemFont(ofSize:NSFont.systemFontSize),
            .foregroundColor:active ? NSColor.black : NSColor.labelColor
        ]
        let size = (title as NSString).size(withAttributes:attributes)
        (title as NSString).draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attributes)
    }
}

final class Reader: NSObject, NSApplicationDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    var window: NSWindow!
    var appearanceButton: NSButton!
    var pendingOpenURL: URL?
    var readyToOpen = false
    let pdf = SelectionPDFView()
    let caption = NSTextView()
    var hasCaption = false
    let textPDF = SelectionPDFView()
    let mentionLabel = NSTextField(labelWithString: "No matches")
    var previousMentionButton: NSButton!
    var nextMentionButton: NSButton!
    var allHighlights: [PDFSelection] = []
    var mentions: [PDFSelection] = []
    var mentionIndex = 0
    let number = NSTextField(string: "")
    let textQuery = NSSearchField()
    var textResults: [PDFSelection] = []
    var textResultIndex = 0
    enum SearchMode { case figure, text }
    var searchMode: SearchMode = .figure
    let status = NSTextField(labelWithString: "Open a PDF to begin. Papers stay on your Mac.")
    let pageLabel = NSTextField(labelWithString: "Page 0 / 0")
    var document: PDFDocument?
    var pageIndex = 0
    var manualCaption = false
    var detectedCaptions: [(page: Int, text: String, font: NSFont?)] = []
    var clickMonitor: Any?
    var figureTypes = FigureTypes(pages:[])
    var pendingSearch: DispatchWorkItem?
    var searchGeneration = 0
    var pdfMouseDown: (view:SelectionPDFView, point:NSPoint)?
    var pdfDragOccurred = false
    var autosaveWork: DispatchWorkItem?
    enum AnnotationTool { case none, highlight, remove }
    var annotationTool: AnnotationTool = .none
    var highlightButton: NSButton!
    var removeButton: NSButton!
    var highlightStore: HighlightStore?
    var lastPDF: PDFView?
    var clickedHighlight: (page:PDFPage,annotation:PDFAnnotation)?
    var originalURL: URL?
    let highlightColors = NSPopUpButton()
    var paperTitle = "Paper Reader"


    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "Quit Paper Reader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); appItem.submenu = appMenu
        let editItem = NSMenuItem(); menu.addItem(editItem); let editMenu = NSMenu(title:"Edit"); editItem.submenu = editMenu
        editMenu.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        editMenu.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        editMenu.addItem(withTitle:"Select All",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        let findItem = NSMenuItem(); menu.addItem(findItem)
        let findMenu = NSMenu(title:"Find"); findItem.submenu = findMenu
        let findTextItem = findMenu.addItem(withTitle:"Find Text",action:#selector(focusTextSearch),keyEquivalent:"f")
        findTextItem.target = self
        let findFigureItem = findMenu.addItem(withTitle:"Find Figure",action:#selector(focusFigureSearch),keyEquivalent:"f")
        findFigureItem.keyEquivalentModifierMask = [.command,.shift]
        findFigureItem.target = self
        let fileItem = NSMenuItem(); menu.insertItem(fileItem,at:1)
        let fileMenu = NSMenu(title:"File"); fileItem.submenu = fileMenu
        let saveItem = fileMenu.addItem(withTitle:"Save",action:#selector(saveCurrentPDF),keyEquivalent:"s")
        saveItem.keyEquivalentModifierMask = [.command]; saveItem.target = self
        for (title,action,key,modifiers) in [
            ("Highlight Selection",#selector(highlightSelection),"h",NSEvent.ModifierFlags([.command,.shift])),
            ("Remove Highlight",#selector(removeHighlight),"",NSEvent.ModifierFlags.command),
            ("Undo Highlight",#selector(undoHighlight),"z",NSEvent.ModifierFlags.command),
            ("Redo Highlight",#selector(redoHighlight),"z",NSEvent.ModifierFlags([.command,.shift]))
        ] {
            let item = editMenu.addItem(withTitle:title,action:action,keyEquivalent:key)
            item.keyEquivalentModifierMask = modifiers; item.target = self
        }
        NSApp.mainMenu = menu
        for view in [pdf,textPDF] {
            view.interactionBegan = { [weak self] in self?.cancelPendingSearch() }
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp,.scrollWheel]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handlePDFInteraction(event)
        }
        NotificationCenter.default.addObserver(self,selector:#selector(pageChanged),name:.PDFViewPageChanged,object:pdf)
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1250,height: 850), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "Paper Reader"; window.minSize = NSSize(width: 900,height: 600)
        let root = NSView()
        window.contentView = root
        let toolbar = NSStackView(views: [button("Open PDF…", #selector(openPDF)), button("‹ Page", #selector(previousPage)), pageLabel, button("Page ›", #selector(nextPage))])
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1),for:.horizontal)
        appearanceButton = NSButton(image:NSImage(systemSymbolName:"sun.max",accessibilityDescription:"Switch appearance")!,target:self,action:#selector(toggleAppearance))
        appearanceButton.bezelStyle = .texturedRounded
        appearanceButton.widthAnchor.constraint(equalToConstant:32).isActive = true
        highlightColors.addItems(withTitles:["Yellow","Green","Blue","Pink","Purple"])
        highlightColors.toolTip = "Manual highlight color"
        highlightColors.widthAnchor.constraint(equalToConstant:90).isActive = true
        highlightButton = AnnotationToolButton(title:"Highlight",target:self,action:#selector(highlightSelection))
        highlightButton.setButtonType(.toggle)
        highlightButton.toolTip = "Highlight selected text, or toggle highlighting mode (⌘⇧H)"
        removeButton = AnnotationToolButton(title:"Remove",target:self,action:#selector(removeHighlight))
        removeButton.setButtonType(.toggle)
        removeButton.toolTip = "Remove a chosen highlight, or toggle click-to-remove mode"
        toolbar.addArrangedSubview(spacer)
        toolbar.addArrangedSubview(highlightButton)
        toolbar.addArrangedSubview(highlightColors)
        toolbar.addArrangedSubview(removeButton)
        toolbar.distribution = .fill
        toolbar.addArrangedSubview(appearanceButton)
        updateAppearanceButton()
        number.widthAnchor.constraint(equalToConstant: 130).isActive = true
        number.placeholderString = "2, Fig. 2, or 2b"; number.delegate = self
        number.target = self; number.action = #selector(findPassages)
        root.addSubview(toolbar)
        let left = NSSplitView(); left.isVertical = false; left.dividerStyle = .thin
        pdf.autoScales = true; pdf.displayMode = .singlePageContinuous; pdf.displayDirection = .vertical
        caption.font = CaptionDetector.captionFont(); caption.isRichText = true
        caption.string = "Autodetected caption appears here after figure search"
        left.addArrangedSubview(panel("FIGURE PANE · Scroll freely to the figure you want", content: pdf))
        let captionHeader = NSView()
        let captionLabel = NSTextField(labelWithString:"CAPTION")
        captionLabel.font = .systemFont(ofSize:11,weight:.semibold)
        captionLabel.textColor = .secondaryLabelColor
        let selectCaptionButton = button("Select caption on my own...",#selector(useSelectedCaption))
        selectCaptionButton.controlSize = .small
        selectCaptionButton.font = .systemFont(ofSize:11)
        selectCaptionButton.toolTip = "Select caption text in either PDF, then click to use it."
        for view in [captionLabel,selectCaptionButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            captionHeader.addSubview(view)
        }
        NSLayoutConstraint.activate([
            captionLabel.leadingAnchor.constraint(equalTo:captionHeader.leadingAnchor),
            captionLabel.centerYAnchor.constraint(equalTo:captionHeader.centerYAnchor),
            selectCaptionButton.trailingAnchor.constraint(equalTo:captionHeader.trailingAnchor),
            selectCaptionButton.centerYAnchor.constraint(equalTo:captionHeader.centerYAnchor),
            selectCaptionButton.leadingAnchor.constraint(greaterThanOrEqualTo:captionLabel.trailingAnchor,constant:8)
        ])
        let captionSection = verticalPanel(header:captionHeader,headerHeight:24,content:scroll(caption))
        let captionContainer = NSView()
        captionSection.translatesAutoresizingMaskIntoConstraints = false
        captionContainer.addSubview(captionSection)
        NSLayoutConstraint.activate([
            captionSection.topAnchor.constraint(equalTo:captionContainer.topAnchor,constant:8),
            captionSection.leadingAnchor.constraint(equalTo:captionContainer.leadingAnchor),
            captionSection.trailingAnchor.constraint(equalTo:captionContainer.trailingAnchor),
            captionSection.bottomAnchor.constraint(equalTo:captionContainer.bottomAnchor)
        ])
        left.addArrangedSubview(captionContainer)
        textPDF.autoScales = true; textPDF.displayMode = .singlePageContinuous; textPDF.displayDirection = .vertical
        previousMentionButton = button("‹ Previous mention", #selector(previousMention))
        nextMentionButton = button("Next mention ›", #selector(nextMention))
        previousMentionButton.isEnabled = false; nextMentionButton.isEnabled = false
        let navigation = NSStackView(views: [previousMentionButton, mentionLabel, nextMentionButton])
        let figureSearch = NSStackView(views:[NSTextField(labelWithString:"Find figure"),number,button("Find",#selector(findPassages))])
        textQuery.placeholderString = "Search paper text"; textQuery.delegate = self
        // Debouncing is owned by Reader. Disable NSSearchField's independent
        // delayed action so it cannot restart a canceled search on focus loss.
        textQuery.sendsWholeSearchString = true
        (textQuery.cell as? NSSearchFieldCell)?.sendsActionOnEndEditing = false
        textQuery.target = self; textQuery.action = #selector(findText)
        textQuery.widthAnchor.constraint(greaterThanOrEqualToConstant:160).isActive = true
        let textSearch = NSStackView(views:[NSTextField(labelWithString:"Find text"),textQuery,button("Find",#selector(findText))])
        let searchHeader = NSView()
        let rows = [figureSearch,textSearch,navigation]
        for (index,row) in rows.enumerated() {
            row.translatesAutoresizingMaskIntoConstraints = false; searchHeader.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo:searchHeader.topAnchor,constant:CGFloat(index)*32),
                row.leadingAnchor.constraint(equalTo:searchHeader.leadingAnchor),
                row.trailingAnchor.constraint(equalTo:searchHeader.trailingAnchor),
                row.heightAnchor.constraint(equalToConstant:28)
            ])
        }
        let right = verticalPanel(header:searchHeader, headerHeight:92,
            content:panel("READING PANE · Both searches jump within this PDF", content:textPDF))
        let mainSplit = BalancedSplitView(left:left,right:right)
        root.addSubview(mainSplit); root.addSubview(status)
        for view in [toolbar, mainSplit, status] { view.translatesAutoresizingMaskIntoConstraints = false }
        // Anchor the reader between the toolbar and footer so it consumes all
        // remaining height, including when the window is enlarged.
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo:root.topAnchor,constant:10),
            toolbar.heightAnchor.constraint(equalToConstant:32),
            status.heightAnchor.constraint(equalToConstant:18),
            toolbar.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:16),
            toolbar.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-16),
            mainSplit.topAnchor.constraint(equalTo:toolbar.bottomAnchor,constant:12),
            mainSplit.leadingAnchor.constraint(equalTo:toolbar.leadingAnchor),
            mainSplit.trailingAnchor.constraint(equalTo:toolbar.trailingAnchor),
            mainSplit.bottomAnchor.constraint(equalTo:status.topAnchor,constant:-10),
            status.leadingAnchor.constraint(equalTo:toolbar.leadingAnchor),
            status.trailingAnchor.constraint(equalTo:toolbar.trailingAnchor),
            status.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-12)
        ])
        toolbar.setContentHuggingPriority(.required,for:.vertical)
        status.setContentHuggingPriority(.required,for:.vertical)
        toolbar.setContentCompressionResistancePriority(.required,for:.vertical)
        status.setContentCompressionResistancePriority(.required,for:.vertical)
        root.layoutSubtreeIfNeeded()
        applyBackgroundColors()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        left.setPosition(max(200,left.bounds.height-180),ofDividerAt: 0)
        readyToOpen = true
        if let url = pendingOpenURL {
            pendingOpenURL = nil
            _ = openDocument(at:url)
        }
    }
    @objc func focusTextSearch() {
        window.makeFirstResponder(textQuery)
        textQuery.selectText(nil)
    }
    @objc func focusFigureSearch() {
        window.makeFirstResponder(number)
        number.selectText(nil)
    }
    @objc func toggleAppearance() {
        let dark = window.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        NSApp.appearance = NSAppearance(named:dark ? .aqua : .darkAqua)
        applyBackgroundColors()
        updateAppearanceButton()
    }
    func applyBackgroundColors() {
        let dark = window.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let background = dark ? NSColor.windowBackgroundColor : NSColor(srgbRed:0.92,green:0.94,blue:0.96,alpha:1)
        let canvas = dark ? NSColor.underPageBackgroundColor : NSColor(srgbRed:0.87,green:0.90,blue:0.93,alpha:1)
        window.backgroundColor = background
        pdf.backgroundColor = canvas
        textPDF.backgroundColor = canvas
        applyCaptionAppearance()
    }
    func applyCaptionAppearance() {
        caption.appearance = hasCaption ? NSAppearance(named:.aqua) : nil
        let background = hasCaption ? NSColor.white : (window.backgroundColor ?? NSColor.windowBackgroundColor)
        caption.backgroundColor = background
        caption.enclosingScrollView?.backgroundColor = background
        caption.insertionPointColor = hasCaption ? .black : .textColor
        if hasCaption {
            caption.textColor = .black
        } else {
            caption.font = .systemFont(ofSize:11,weight:.semibold)
            caption.textColor = .secondaryLabelColor
        }
    }
    func setCaptionPlaceholder(_ message: String) {
        hasCaption = false
        caption.string = message
        applyCaptionAppearance()
    }
    func updateAppearanceButton() {
        let dark = window.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        appearanceButton.image = NSImage(systemSymbolName:dark ? "sun.max" : "moon",accessibilityDescription:dark ? "Switch to light mode" : "Switch to dark mode")
        appearanceButton.toolTip = dark ? "Switch to light mode" : "Switch to dark mode"
        appearanceButton.setAccessibilityLabel(appearanceButton.toolTip)
    }
    func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title,target: self,action: action) }
    func scroll(_ text: NSTextView) -> NSScrollView {
        let view = NSScrollView(); view.hasVerticalScroller = true; view.drawsBackground = true
        text.frame = NSRect(x:0,y:0,width:500,height:500); text.minSize = NSSize(width:0,height:0); text.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        view.documentView = text
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        return view
    }
    // Fixed-size headers plus explicitly pinned content avoid stack views
    // stretching their header rows and leaving blank space above the PDFs.
    func verticalPanel(header: NSView, headerHeight: CGFloat, content: NSView) -> NSView {
        let container = NSView()
        for view in [header,content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo:container.topAnchor),
            header.leadingAnchor.constraint(equalTo:container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo:container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant:headerHeight),
            content.topAnchor.constraint(equalTo:header.bottomAnchor,constant:8),
            content.leadingAnchor.constraint(equalTo:container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo:container.trailingAnchor),
            content.bottomAnchor.constraint(equalTo:container.bottomAnchor)
        ])
        return container
    }
    func panel(_ title: String,content: NSView) -> NSView {
        let label = NSTextField(labelWithString:title)
        label.font = .systemFont(ofSize:11,weight:.semibold)
        label.textColor = .secondaryLabelColor
        return verticalPanel(header:label,headerHeight:16,content:content)
    }
    @objc func openPDF() {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.pdf]; picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        _ = openDocument(at:url)
    }
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath:filename)
        guard readyToOpen else { pendingOpenURL = url; return true }
        return openDocument(at:url)
    }
    @discardableResult func openDocument(at url: URL) -> Bool {
        guard let sourceData = try? Data(contentsOf:url), let loaded = PDFDocument(data:sourceData) else {
            let alert = NSAlert(); alert.messageText = "Could not open PDF"
            alert.informativeText = "The file could not be read as a PDF: " + url.lastPathComponent
            alert.runModal(); return false
        }
        guard confirmUnsavedChanges() else { return false }
        cancelPendingSearch()
        document = loaded; pdf.document = loaded
        // Separate documents keep selections and navigation independent.
        textPDF.document = PDFDocument(data:sourceData)
        originalURL = url; lastPDF = nil; clickedHighlight = nil
        setAnnotationTool(.none)
        if let right = textPDF.document {
            highlightStore = HighlightStore(left:loaded,right:right)
            highlightStore?.didChange = { [weak self] in self?.refreshAnnotations() }
        }
        pageIndex = 0; setCaptionPlaceholder("Autodetected caption appears here after figure search")
        textResults = []; textResultIndex = 0
        previousMentionButton.isEnabled = false; nextMentionButton.isEnabled = false
        mentionLabel.stringValue = "No text matches"
        status.stringValue = "Reading searchable text…"
        figureTypes = FigureTypes(pages:(0..<loaded.pageCount).map { loaded.page(at:$0)?.string ?? "" })
        allHighlights = makeHighlights(in:textPDF.document)
        textPDF.highlightedSelections = allHighlights
        pdf.highlightedSelections = makeHighlights(in:document)
        if FigureSearch.query(number.stringValue) != nil { findPassages() }
        else {
            mentions = []; mentionIndex = 0; detectedCaptions = []
            previousMentionButton.isEnabled = false; nextMentionButton.isEnabled = false
            mentionLabel.stringValue = "All references"
            status.stringValue = "\(allHighlights.count) figure references highlighted. Click one or search a figure number."
        }
        if !textQuery.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { findText() }
        paperTitle = "Paper Reader"
        window.title = paperTitle; window.isDocumentEdited = false; showPage()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        return true
    }
    func showPage() {
        guard let document, let page = document.page(at: pageIndex) else { return }
        pageLabel.stringValue = "Page \(pageIndex+1) / \(document.pageCount)"; pdf.go(to: page)
    }
    @objc func pageChanged() {
        guard let document, let page = pdf.currentPage else { return }
        pageIndex = document.index(for:page)
        pageLabel.stringValue = "Page \(pageIndex+1) / \(document.pageCount)"
        updateCaption()
    }
    @objc func previousPage() { guard document != nil else { return }; pageIndex = max(0,pageIndex-1); showPage() }
    @objc func nextPage() { guard let document else { return }; pageIndex = min(document.pageCount-1,pageIndex+1); showPage() }
    func cancelPendingSearch() {
        searchGeneration += 1
        pendingSearch?.cancel()
        pendingSearch = nil
    }
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === textQuery || field === number else { return }
        cancelPendingSearch()
        let generation = searchGeneration
        let isTextSearch = field === textQuery
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.searchGeneration == generation else { return }
            if isTextSearch { self.findText() } else { self.findPassages() }
        }
        pendingSearch = work; DispatchQueue.main.asyncAfter(deadline:.now()+0.25,execute:work)
    }
    func handlePDFInteraction(_ event: NSEvent) -> NSEvent? {
        let hit = [pdf,textPDF].first {
            let point = $0.convert(event.locationInWindow,from:nil)
            return $0.bounds.contains(point) && $0.visibleRect.contains(point)
        }
        if event.type == .scrollWheel {
            if hit != nil { cancelPendingSearch() }
            return event
        }
        if event.type == .leftMouseDown {
            pdfMouseDown = nil; pdfDragOccurred = false
            guard let view = hit else { return event }
            cancelPendingSearch()
            lastPDF = view
            pdfMouseDown = (view,event.locationInWindow)
            view.suppressLinkActions = true
            clickedHighlight = nil
            let point = view.convert(event.locationInWindow,from:nil)
            if let page = view.page(for:point,nearest:false) {
                let position = view.convert(point,to:page)
                if let annotation = page.annotations.reversed().first(where:{ HighlightStore.isHighlight($0) && $0.bounds.contains(position) }) {
                    clickedHighlight = (page,annotation)
                    if annotationTool == .remove || event.modifierFlags.contains(.option) {
                        pdfMouseDown = nil; view.suppressLinkActions = false
                        removeClickedHighlight(); return nil
                    }
                }
            }
        } else if event.type == .leftMouseDragged {
            if let down = pdfMouseDown, hypot(event.locationInWindow.x-down.point.x,event.locationInWindow.y-down.point.y) > 3 {
                pdfDragOccurred = true
            }
        } else if event.type == .leftMouseUp, let down = pdfMouseDown {
            let click = !pdfDragOccurred && event.clickCount == 1 && !event.modifierFlags.contains(.shift)
                && hypot(event.locationInWindow.x-down.point.x,event.locationInWindow.y-down.point.y) <= 3
                && hit === down.view
            let tool = annotationTool
            pdfMouseDown = nil
            // PDFKit may process the native link after its mouse-up callback.
            // Keep suppression active until the gesture has completely unwound.
            DispatchQueue.main.async { [weak self] in
                down.view.suppressLinkActions = false
                guard let self else { return }
                if tool == .highlight && self.annotationTool == .highlight {
                    self.lastPDF = down.view
                    self.applySelectedHighlight()
                } else if tool == .none && self.annotationTool == .none && click {
                    if down.view === self.textPDF {
                        let handled = self.handleReferenceClick(event)
                        if !handled, let action = self.linkAction(in:down.view,event:event) as? PDFActionURL {
                            down.view.perform(action)
                        }
                    } else if let action = self.linkAction(in:down.view,event:event) {
                        down.view.perform(action)
                    }
                }
            }
        }
        return event
    }
    func linkAction(in view: PDFView, event: NSEvent) -> PDFAction? {
        let point = view.convert(event.locationInWindow,from:nil)
        guard let page = view.page(for:point,nearest:false),
              let link = page.annotations.first(where:{ $0.type == "Link" && $0.bounds.contains(view.convert(point,to:page)) }) else { return nil }
        if let action = link.action { return action }
        if let destination = link.destination { return PDFActionGoTo(destination:destination) }
        return nil
    }
    @objc func findText() {
        searchMode = .text
        cancelPendingSearch()
        textResults = []; textResultIndex = 0
        previousMentionButton.isEnabled = false; nextMentionButton.isEnabled = false
        textPDF.clearSelection()
        let query = textQuery.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let document = textPDF.document else { status.stringValue = "Open a PDF first."; return }
        guard !query.isEmpty else { mentionLabel.stringValue = "No text search"; return }
        textResults = document.findString(query,withOptions:[.caseInsensitive])
        guard !textResults.isEmpty else {
            mentionLabel.stringValue = "No matches"
            status.stringValue = "No text matches for ‘\(query)’. PDF positions unchanged."; return
        }
        showTextResult()
    }
    func showTextResult() {
        guard textResults.indices.contains(textResultIndex) else { return }
        let selection = textResults[textResultIndex]
        textPDF.setCurrentSelection(selection,animate:false)
        textPDF.go(to:selection)
        let page = selection.pages.first.map { (textPDF.document?.index(for:$0) ?? 0)+1 } ?? 1
        mentionLabel.stringValue = "Text · \(textResultIndex+1) / \(textResults.count) · p. \(page)"
        previousMentionButton.isEnabled = textResultIndex > 0
        nextMentionButton.isEnabled = textResultIndex+1 < textResults.count
        status.stringValue = ""
    }
    func makeHighlights(in document: PDFDocument?) -> [PDFSelection] {
        guard let document else { return [] }
        var highlights: [PDFSelection] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at:index), let text = page.string else { continue }
            for reference in FigureSearch.references(text) {
                guard let selection = page.selection(for:figureTypes.highlightRange(for:reference.range,in:text)) else { continue }
                selection.color = figureTypes.type(before:reference.range,in:text) == nil
                    ? NSColor(srgbRed:0.62,green:0.43,blue:0.81,alpha:0.50)
                    : NSColor(srgbRed:0.84,green:0.62,blue:0.59,alpha:0.32)
                highlights.append(selection)
            }
        }
        return highlights
    }
    @objc func findPassages() {
        cancelPendingSearch()
        searchMode = .figure
        mentions = []; mentionIndex = 0; detectedCaptions = []; manualCaption = false
        textPDF.highlightedSelections = allHighlights; textPDF.clearSelection()
        previousMentionButton.isEnabled = false; nextMentionButton.isEnabled = false
        mentionLabel.stringValue = "No matches"
        guard let searchDocument = textPDF.document else { status.stringValue = "Open a PDF first."; return }
        guard let value = FigureSearch.query(number.stringValue) else {
            status.stringValue = "\(allHighlights.count) references highlighted. Enter a figure number to navigate its mentions."; return
        }
        var hasText = false
        for index in 0..<searchDocument.pageCount {
            guard let page = searchDocument.page(at:index), let text = page.string else { continue }
            if !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { hasText = true }
            for range in FigureSearch.matches(text,figure:value) {
                guard let selection = page.selection(for:range) else { continue }
                mentions.append(selection)

            }
        }
        detectedCaptions = CaptionDetector.captions(in:searchDocument,figure:value)
        textPDF.highlightedSelections = allHighlights
        updateCaption()
        if mentions.isEmpty {
            status.stringValue = hasText ? "No explicit mentions of Figure \(value). Try its main number. Grouped references may not all be detected." : "No searchable text in this PDF. Scanned papers need OCR."
        } else { showMention() }
    }
    func handleReferenceClick(_ event: NSEvent) -> Bool {
        let point = textPDF.convert(event.locationInWindow,from:nil)
        guard textPDF.visibleRect.contains(point),
              let page = textPDF.page(for:point,nearest:false),
              let text = page.string else { return false }
        let pagePoint = textPDF.convert(point,to:page)
        for reference in FigureSearch.references(text) {
            guard let selection = page.selection(for:figureTypes.highlightRange(for:reference.range,in:text)),
                  selection.selectionsByLine().contains(where: { $0.bounds(for:page).insetBy(dx:-2,dy:-2).contains(pagePoint) }) else { continue }
            navigateToFigure(reference.figure, sourcePage:textPDF.document?.index(for:page) ?? 0)
            return true
        }
        // Native internal PDF links also navigate only the left document.
        if let annotation = page.annotations.first(where:{ $0.type == "Link" && $0.bounds.contains(pagePoint) }),
           let destination = (annotation.action as? PDFActionGoTo)?.destination ?? annotation.destination,
           let targetPage = destination.page,
           let index = textPDF.document?.index(for:targetPage),
           let leftPage = document?.page(at:index) {
            pdf.go(to:PDFDestination(page:leftPage,at:destination.point))
            status.stringValue = "Opened linked location on the left. Right pane stays in place."
            return true
        }
        return false
    }
    func navigateToFigure(_ figure: String, sourcePage: Int) {
        guard let document else { return }
        cancelPendingSearch()
        let main = String(figure.prefix { $0.isNumber })
        let candidates = CaptionDetector.captions(in:document,figure:main)
        guard let target = candidates.min(by: { abs($0.page-sourcePage) < abs($1.page-sourcePage) }),
              let page = document.page(at:target.page) else {
            status.stringValue = "Could not locate Figure \(figure)’s caption. Left and right positions unchanged."
            return
        }
        // Do not run findPassages here: it would move the right PDF.
        detectedCaptions = candidates; manualCaption = false
        pageIndex = target.page
        pdf.go(to:page)
        updateCaption()
        status.stringValue = "Figure \(figure) · page \(target.page+1) opened on the left. Right pane stays in place."
    }
    func setCaption(_ text: String, font: NSFont? = nil) {
        hasCaption = true
        applyCaptionAppearance()
        caption.textStorage?.setAttributedString(CaptionDetector.display(text,font:font))
    }
    func updateCaption() {
        guard !manualCaption else { return }
        guard let candidate = detectedCaptions.min(by: { abs($0.page-pageIndex) < abs($1.page-pageIndex) }) else {
            setCaptionPlaceholder("Autodetected caption appears here after figure search")
            return
        }
        setCaption(candidate.text,font:candidate.font)
    }
    @objc func useSelectedCaption() {
        let selection = pdf.currentSelection ?? textPDF.currentSelection
        let selected = selection?.string
        guard let selected, !selected.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            status.stringValue = "Select caption text in either PDF, then click ‘Select caption on my own...’."
            return
        }
        manualCaption = true
        setCaption(selected,font:CaptionDetector.sourceFont(in:selection?.attributedString))
        status.stringValue = "Caption set from selected text."
    }
    func showMention() {
        guard mentions.indices.contains(mentionIndex) else { return }
        let selection = mentions[mentionIndex]
        textPDF.clearSelection()
        textPDF.go(to:selection)
        // Keep persistent lilac overlays after the search field regains focus.
        textPDF.highlightedSelections = allHighlights
        let page = selection.pages.first.map { (textPDF.document?.index(for:$0) ?? 0)+1 } ?? 1
        mentionLabel.stringValue = "Figure · \(mentionIndex+1) / \(mentions.count) · p. \(page)"
        previousMentionButton.isEnabled = mentionIndex > 0
        nextMentionButton.isEnabled = mentionIndex+1 < mentions.count
        status.stringValue = ""
        status.toolTip = nil
    }
    @objc func previousMention() {
        cancelPendingSearch()
        if searchMode == .text {
            guard textResultIndex > 0 else { return }; textResultIndex -= 1; showTextResult()
        } else {
            guard mentionIndex > 0 else { return }; mentionIndex -= 1; showMention()
        }
    }
    @objc func nextMention() {
        cancelPendingSearch()
        if searchMode == .text {
            guard textResultIndex+1 < textResults.count else { return }; textResultIndex += 1; showTextResult()
        } else {
            guard mentionIndex+1 < mentions.count else { return }; mentionIndex += 1; showMention()
        }
    }
    func refreshAnnotations() {
        window.isDocumentEdited = highlightStore?.isDirty ?? false
        pdf.documentView?.needsDisplay = true
        textPDF.documentView?.needsDisplay = true
        pdf.needsDisplay = true; textPDF.needsDisplay = true
        autosaveWork?.cancel()
        if highlightStore?.isDirty == true {
            let work = DispatchWorkItem { [weak self] in _ = self?.saveToOriginal() }
            autosaveWork = work
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)
        }
    }
    func setAnnotationTool(_ tool: AnnotationTool) {
        annotationTool = tool
        highlightButton.state = tool == .highlight ? .on : .off
        removeButton.state = tool == .remove ? .on : .off
        switch tool {
        case .highlight: status.stringValue = "Highlight is on. Select text to highlight it; click Highlight again to turn it off."
        case .remove: status.stringValue = "Remove is on. Click manual highlights to remove them; click Remove again to turn it off."
        case .none: status.stringValue = ""
        }
    }
    @objc func highlightSelection() {
        guard highlightStore != nil else { setAnnotationTool(.none); status.stringValue = "Open a PDF first."; return }
        if annotationTool == .highlight { setAnnotationTool(.none); return }
        let source = lastPDF ?? textPDF
        if let text = source.currentSelection?.string, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            setAnnotationTool(.none)
            applySelectedHighlight()
        } else {
            setAnnotationTool(.highlight)
        }
    }
    func applySelectedHighlight() {
        guard let store = highlightStore else { return }
        let source = lastPDF ?? textPDF
        guard let selection = source.currentSelection, !(selection.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        let colors: [NSColor] = [.systemYellow,.systemGreen,.systemBlue,.systemPink,.systemPurple]
        let color = colors[max(0,highlightColors.indexOfSelectedItem)].withAlphaComponent(0.4)
        let count = store.highlight(selection,color:color)
        source.clearSelection()
        clickedHighlight = nil
        status.stringValue = count > 0 ? "Highlighted. Autosaving…" : "Could not highlight this selection."
    }
    @objc func removeHighlight() {
        guard highlightStore != nil else { setAnnotationTool(.none); status.stringValue = "Open a PDF first."; return }
        if annotationTool == .remove { setAnnotationTool(.none); return }
        if let clicked = clickedHighlight, clicked.page.annotations.contains(where: { $0 === clicked.annotation }) {
            setAnnotationTool(.none); removeClickedHighlight()
        } else {
            setAnnotationTool(.remove)
        }
    }
    func removeClickedHighlight() {
        guard let store = highlightStore, let clicked = clickedHighlight else { return }
        _ = store.remove(page:clicked.page,annotation:clicked.annotation)
        clickedHighlight = nil
        status.stringValue = "Highlight removed. Autosaving…"
    }
    @objc func undoHighlight() {
        if let responder = window.firstResponder as? NSTextView, responder !== pdf.documentView, responder !== textPDF.documentView,
           responder.undoManager?.canUndo == true { responder.undoManager?.undo(); return }
        highlightStore?.undoManager.undo()
    }
    @objc func redoHighlight() { highlightStore?.undoManager.redo() }
    @objc func saveCurrentPDF() { _ = saveToOriginal() }
    @discardableResult func saveToOriginal() -> Bool {
        autosaveWork?.cancel(); autosaveWork = nil
        guard let store = highlightStore, let url = originalURL else {
            status.stringValue = "Open a PDF first."; return false
        }
        guard store.isDirty else { return true }
        do {
            try store.save(to:url)
            status.stringValue = "Saved."
            return true
        } catch {
            status.stringValue = "Autosave failed: " + error.localizedDescription
            return false
        }
    }
    func confirmUnsavedChanges() -> Bool {
        guard highlightStore?.isDirty == true else { return true }
        if saveToOriginal() { return true }
        let alert = NSAlert(); alert.messageText = "Could not autosave this PDF"
        alert.informativeText = "Your highlights are still in memory. Check that the file is writable, then retry."
        alert.addButton(withTitle:"Retry Save"); alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:"Discard")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveToOriginal()
        case .alertThirdButtonReturn: highlightStore?.markSaved(); return true
        default: return false
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { confirmUnsavedChanges() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        confirmUnsavedChanges() ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = Reader()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

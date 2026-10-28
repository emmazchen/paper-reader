import Foundation
func check(_ condition: Bool, _ name: String) { if !condition { fatalError(name) } }
check(FigureSearch.query("Fig. 2") == "2", "Accept Fig. prefix")
check(FigureSearch.query("Figure 2b") == "2b", "Accept panel")
check(FigureSearch.query(" 2 ") == "2", "Trim input")
check(FigureSearch.query("anything") == nil, "Reject invalid input")
let text = FigureSearch.normalize("Results in Fig.\n2a show improvement. Figure 20 differs. See Figure 2.")
check(FigureSearch.matches(text,figure:"2").count == 2, "Line breaks, panels, and no Figure 20 false positive")
check(FigureSearch.matches(text,figure:"2a").count == 1, "Specific panel")
check(FigureSearch.matches("Figure 2b shows results",figure:"2a").isEmpty, "Do not match wrong panel")
check(!FigureSearch.sentences(text).isEmpty, "Sentence extraction")
check(FigureSearch.sentences(text).reduce(0) { $0 + FigureSearch.matches($1,figure:"2").count } == 2, "Sentence splitting preserves references")
print("8 search checks passed")

// Original UTF-16 offsets must survive emoji and PDF line breaks.
let raw = "🧪 Results are shown in Fig.\n2a and improve accuracy. Figure 20 differs."
let ranges = FigureSearch.mentionSentenceRanges(raw,figure:"2")
check(ranges.count == 1, "One mentioning sentence")
check((raw as NSString).substring(with:ranges[0]).contains("Fig.\n2a"), "Keep original PDF offsets")
check(FigureSearch.mentionSentenceRanges(raw,figure:"9").isEmpty, "No highlights for missing figure")

import PDFKit
import CoreText
import CoreGraphics
let data = NSMutableData()
let consumer = CGDataConsumer(data:data as CFMutableData)!
var box = CGRect(x:0,y:0,width:612,height:792)
let context = CGContext(consumer:consumer,mediaBox:&box,nil)!
context.beginPDFPage(nil)
context.textPosition = CGPoint(x:50,y:700)
let line = CTLineCreateWithAttributedString(NSAttributedString(string:"Results in Figure 2 show improved accuracy.",attributes:[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,14,nil)]))
CTLineDraw(line,context)
context.endPDFPage(); context.closePDF()
let pdf = PDFDocument(data:data as Data)!
let page = pdf.page(at:0)!
let pdfRanges = FigureSearch.mentionSentenceRanges(page.string!,figure:"2")
check(pdfRanges.count == 1, "Find sentence in actual PDF text")
let selection = page.selection(for:pdfRanges[0])!
check(selection.string!.contains("Figure 2"), "PDFKit selects mentioning sentence")
check(!selection.bounds(for:page).isEmpty, "Highlight has page geometry")
check(page.annotations.isEmpty, "Search adds no permanent annotations")
print("7 PDF range and selection checks passed")

func captionLine(_ text: String, _ x: CGFloat, _ y: CGFloat, _ height: CGFloat = 12) -> CaptionLine {
    CaptionLine(text:text,bounds:CGRect(x:x,y:y,width:230,height:height))
}
let captionLines = [
    captionLine("As shown in Figure 2, results improve.",50,730),
    captionLine("Figure 20: Wrong figure.",50,650),
    captionLine("Fig. 2: Example caption.",50,600),
    captionLine("The second sentence explains panel (a).",50,584),
    captionLine("Panel (b) measures accuracy.",50,568),
    captionLine("Unrelated right-column paragraph.",320,584),
    captionLine("Body text after a large gap.",50,510),
    captionLine("Figure 3: A different caption.",50,450)
]
let detected = CaptionDetector.captions(in:captionLines,figure:"2")
check(detected.count == 1, "Caption is separate from in-text references")
check(detected[0].contains("Panel (b)"), "Keep multiple caption sentences")
check(!detected[0].contains("right-column"), "Exclude adjacent column")
check(!detected[0].contains("Body text"), "Stop at vertical gap")
check(CaptionDetector.captions(in:captionLines,figure:"2b") == detected, "Panel query finds parent caption")
let split = [captionLine("Figure",50,600),captionLine("2 | Split label caption.",50,584),captionLine("Additional explanation.",50,568)]
check(CaptionDetector.captions(in:split,figure:"2").first?.contains("Additional explanation") == true, "Split label and number")
let blocks = [captionLine("Figure 2. Caption.",50,600),captionLine("Table 1. Different block.",50,584)]
check(CaptionDetector.captions(in:blocks,figure:"2").first == "Figure 2. Caption.", "Stop at next caption")
check(CaptionDetector.captions(in:captionLines,figure:"9").isEmpty, "Missing caption")

// End-to-end: extract PDFKit lines and detect an actual PDF caption.
let capData = NSMutableData()
let capContext = CGContext(consumer:CGDataConsumer(data:capData as CFMutableData)!,mediaBox:&box,nil)!
capContext.beginPDFPage(nil)
for (text,y) in [("Figure 2: Caption title.",600.0),("A second caption sentence.",582.0),("Final caption sentence.",564.0)] {
    capContext.textPosition = CGPoint(x:50,y:y)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,12,nil)])),capContext)
}
capContext.endPDFPage(); capContext.closePDF()
let capPage = PDFDocument(data:capData as Data)!.page(at:0)!
let capText = capPage.string!
let extracted = capPage.selection(for:NSRange(location:0,length:(capText as NSString).length))!.selectionsByLine().map { CaptionLine(text:$0.string!,bounds:$0.bounds(for:capPage)) }
check(CaptionDetector.captions(in:extracted,figure:"2").first?.contains("Final caption sentence.") == true, "Detect complete caption from PDFKit lines")
print("9 caption checks passed")

let clickable = "🧪 See Fig.\n2b and Figure 13. Figure 20 differs."
let references = FigureSearch.references(clickable)
check(references.map(\.figure) == ["2b","13","20"], "Clickable references identify any figure")
check((clickable as NSString).substring(with:references[0].range) == "Fig.\n2b", "Clickable reference retains exact glyph offsets")
check(FigureSearch.references("An ordinary paragraph.").isEmpty, "Ordinary text is not clickable")
print("3 clickable-reference checks passed")

let typesText = "Extended Data Fig. 1. extended-data Figure 2. Extended\nData Fig. 3. Extended data Figure 4. Supplemental Fig. 1. Supplementary Figure 2. Supplement Fig. 3. supplemental Figure 4. Pilot Fig. 1. Pilot Figure 2. Pilot Fig. 3. Pilot Figure 4. See Fig. 1. See Fig. 2. See Fig. 3. See Fig. 4."
let types = FigureTypes(pages:[typesText])
check(types.counts["extended data"] == 4, "Soft extended-data variants")
check(types.counts["supplemental"] == 4, "Soft supplemental variants")
check(types.counts["pilot"] == 4, "Learn an unfamiliar prefix")
check(types.counts["see"] == nil, "Ignore ordinary reference language")
let three = FigureTypes(pages:["Pilot Fig. 1. Pilot Fig. 2. Pilot Fig. 3."])
check(three.counts.isEmpty, "Strictly more than three")
let typedRefs = FigureSearch.references(typesText)
check(types.type(before:typedRefs[0].range,in:typesText) == "extended data", "Classify individual reference")
check(types.type(before:typedRefs.last!.range,in:typesText) == nil, "Keep ordinary references lilac")
let acrossPages = FigureTypes(pages:["Pilot Fig. 1.","Pilot Fig. 2.","Pilot Fig. 3.","Pilot Fig. 4."])
check(acrossPages.counts["pilot"] == 4, "Count document-wide")
print("8 figure-type checks passed")

check(CaptionDetector.format("Figure 2. Results. a) First panel. b) Second panel.") == "Figure 2. Results. \n\n• a) First panel. \n\n• b) Second panel.", "Separate a) and b) bullets")
check(CaptionDetector.format("(a) First panel. (b) Second panel.") == "• (a) First panel. \n\n• (b) Second panel.", "Parenthesized panel labels")
check(CaptionDetector.format("Figure 2. A single caption.") == "Figure 2. A single caption.", "Leave captions without panels alone")
check(!CaptionDetector.format("beta) is not a panel label").contains("•"), "Avoid labels inside words")
print("4 caption formatting checks passed")
let formattedLabels = CaptionDetector.format("Figure 2. a) First. (b) Second.")
check(CaptionDetector.formattedLabelRanges(formattedLabels).map { (formattedLabels as NSString).substring(with:$0) } == ["a)","(b)"], "Bold only panel labels")
check(CaptionDetector.formattedLabelRanges("No labels here.").isEmpty, "No bold outside labels")
print("2 bold-label checks passed")

func labels(_ input: String) -> [String] {
    let formatted = CaptionDetector.format(input)
    return CaptionDetector.formattedLabelRanges(formatted).map { (formatted as NSString).substring(with:$0) }
}
check(labels("Figure 2. a, First panel. b, Second panel. c, Third panel.") == ["a,","b,","c,"], "Recurring comma labels")
check(labels("Figure 2. a First panel. b Second panel. c Third panel.") == ["a","b","c"], "Recurring bare letters after periods")
check(labels("Figure 2 | Results a, First panel. b, Second panel.") == ["a,","b,"], "Recover initial a comma from later b pattern")
check(labels("Figure 2. We use a model. A result is shown.").isEmpty, "Do not split ordinary article")
check(labels("Figure 2. a, An isolated letter.").isEmpty, "Require recurring pattern for weak labels")
check(labels("Figure 2. b, Second panel. c, Third panel.") == ["b,","c,"], "Pattern can start with b")
print("6 recurring-label checks passed")
check(pdf.findString("IMPROVED ACCURACY",withOptions:[.caseInsensitive]).first?.string?.lowercased() == "improved accuracy", "Case-insensitive PDF text search")
check(pdf.findString("absent phrase",withOptions:[.caseInsensitive]).isEmpty, "No text results for absent phrase")
print("2 PDF text-search checks passed")

import AppKit
let pdfCaptionFont = NSFont(name:"Times-Roman",size:8)!
let pdfLabelFont = NSFont(name:"Helvetica-Bold",size:10)!
let fontLines = [
    CaptionLine(text:"Figure 2:",bounds:CGRect(x:50,y:600,width:230,height:12),font:pdfLabelFont),
    CaptionLine(text:"a) A much longer caption using the paper's serif font.",bounds:CGRect(x:50,y:584,width:230,height:12),font:pdfCaptionFont)
]
let fontCandidate = CaptionDetector.captionsWithFonts(in:fontLines,figure:"2")[0]
check(fontCandidate.font?.familyName == pdfCaptionFont.familyName, "Extract dominant caption font, not label font")
let displayedCaption = CaptionDetector.display(fontCandidate.text,font:fontCandidate.font)
let bodyRange = (displayedCaption.string as NSString).range(of:"A much longer")
let displayFont = displayedCaption.attribute(.font,at:bodyRange.location,effectiveRange:nil) as! NSFont
check(displayFont.familyName == CaptionDetector.captionFont().familyName, "Display preferred caption font family")
check(displayFont.pointSize == 15, "Use readable size instead of PDF size")
let boldRange = CaptionDetector.formattedLabelRanges(displayedCaption.string)[0]
let boldFont = displayedCaption.attribute(.font,at:boldRange.location,effectiveRange:nil) as! NSFont
check(boldFont.familyName == CaptionDetector.captionFont().familyName && NSFontManager.shared.traits(of:boldFont).contains(.boldFontMask), "Bold label keeps preferred family")
let selectedFont = CaptionDetector.sourceFont(in:NSAttributedString(string:"Selected caption",attributes:[.font:pdfCaptionFont]))
check(selectedFont?.fontName == pdfCaptionFont.fontName, "Manual selection preserves font")
print("5 caption-font checks passed")
let prefixed = "🧪 See Extended-Data Fig. 2 and Supplementary Figure 3."
let prefixedRefs = FigureSearch.references(prefixed)
check((prefixed as NSString).substring(with:types.highlightRange(for:prefixedRefs[0].range,in:prefixed)) == "Extended-Data Fig. 2", "Pink includes full multiword prefix")
check((prefixed as NSString).substring(with:types.highlightRange(for:prefixedRefs[1].range,in:prefixed)) == "Supplementary Figure 3", "Pink includes original soft-matched spelling")
let regular = "See Fig. 2."
let regularRef = FigureSearch.references(regular)[0]
check(types.highlightRange(for:regularRef.range,in:regular) == regularRef.range, "Ordinary reference range unchanged")
print("3 prefix highlight checks passed")

let columnCaption = [
    CaptionLine(text:"Figure 2. a) First panel.",bounds:CGRect(x:50,y:600,width:230,height:12),font:pdfCaptionFont),
    CaptionLine(text:"The left column ends with a complete sentence.",bounds:CGRect(x:50,y:584,width:230,height:12),font:pdfCaptionFont),
    CaptionLine(text:"b) The caption continues in the right column.",bounds:CGRect(x:320,y:600,width:230,height:12),font:pdfCaptionFont),
    CaptionLine(text:"Final right-column explanation.",bounds:CGRect(x:320,y:584,width:230,height:12),font:pdfCaptionFont),
    CaptionLine(text:"Discussion",bounds:CGRect(x:320,y:540,width:230,height:18))
]
check(CaptionDetector.captions(in:columnCaption,figure:"2")[0].contains("Final right-column explanation."),"Follow caption into right column")
print("Column continuation regression passed")
let threeColumns = columnCaption + [CaptionLine(text:"c) Third-column continuation.",bounds:CGRect(x:590,y:600,width:230,height:12),font:pdfCaptionFont)]
check(CaptionDetector.captions(in:threeColumns,figure:"2")[0].contains("Third-column continuation"),"Search additional columns")
let unrelatedColumn = [
    CaptionLine(text:"Figure 2. Caption ends here.",bounds:CGRect(x:50,y:600,width:230,height:12),font:pdfCaptionFont),
    CaptionLine(text:"An unrelated paragraph.",bounds:CGRect(x:320,y:600,width:230,height:12),font:pdfLabelFont)
]
check(!CaptionDetector.captions(in:unrelatedColumn,figure:"2")[0].contains("unrelated"),"Reject different-font adjacent paragraph")
let wrap = [captionLine("Figure 2. Accuracy is measured",50,600),captionLine("across all subjects.",320,600)]
check(CaptionDetector.captions(in:wrap,figure:"2")[0].contains("across all subjects"),"Unfinished sentence can continue without fonts")
let columnData = NSMutableData()
let columnContext = CGContext(consumer:CGDataConsumer(data:columnData as CFMutableData)!,mediaBox:&box,nil)!
columnContext.beginPDFPage(nil)
for (text,x,y) in [("Figure 2. a) First panel.",50.0,600.0),("Left-column explanation.",50.0,584.0),("b) Second panel.",320.0,600.0),("Final caption continuation.",320.0,584.0)] {
    columnContext.textPosition = CGPoint(x:x,y:y)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,10,nil)])),columnContext)
}
columnContext.endPDFPage(); columnContext.closePDF()
let columnPage = PDFDocument(data:columnData as Data)!.page(at:0)!
let columnText = columnPage.string!
let columnLines = columnPage.selection(for:NSRange(location:0,length:(columnText as NSString).length))!.selectionsByLine().map { CaptionLine(text:$0.string!,bounds:$0.bounds(for:columnPage),font:CaptionDetector.sourceFont(in:$0.attributedString)) }
check(CaptionDetector.captions(in:columnLines,figure:"2")[0].contains("Final caption continuation"),"PDFKit two-column caption integration")
print("4 additional column checks passed")

let groupedCaption = "Fig. 3 | Tau is synthesized exclusively in neuronal dendrites. a, First panel. b, Second panel. c, Third panel. d, Fourth panel. e, Reconstruction. f, g, smFISH and STARFISH-Mapt in DIV1 (f) and DIV6 (g) primary hippocampal neurons. h, Quantification."
check(labels(groupedCaption) == ["a,","b,","c,","d,","e,","f, g,","h,"],"Grouped panel labels stay together and inline references stay in prose")
print("Grouped caption regression passed")
check(labels("Figure 4. (a) and (b) Shared explanation. (c) Another panel.") == ["(a) and (b)","(c)"],"Group parenthesized heading labels")
check(labels("Figure 4. (a), (b) Shared explanation. (c) Another panel.") == ["(a), (b)","(c)"],"Group comma-separated parenthesized labels")
check(labels("Figure 4. (a) Results at DIV1 (a) and DIV6 (b). (b) Quantification.") == ["(a)","(b)"],"Do not split inline parenthetical references")
check(labels("Figure 4. a, b, Shared description. c, Next panel.") == ["a, b,","c,"],"Grouped labels generalize to other letters")
print("4 general panel-grouping checks passed")

let rangeCaption = "Fig. 4 | Newly synthesized tau is a dendritic substrate of neuroproteasomes. a–c, Pulse–chase experiments in neurons pre-treated with epoxomicin (a) or iBEp (b). c, Same as a but immunoprecipitating MAP2. d, Micrographs. e, STARFISH labeling."
check(labels(rangeCaption) == ["a–c,","c,","d,","e,"],"Range heading plus individual panel descriptions")
check(labels("Figure 2. a-c, Shared description. d, Next panel. e, Final panel.") == ["a-c,","d,","e,"],"Hyphenated panel range")
check(labels("Figure 2. (a–c) Shared description. (c) More detail. (d) Next panel.") == ["(a–c)","(c)","(d)"],"Parenthesized panel range")
check(labels("Figure 2. a, First panel. b, Second panel. As noted in a, the result improves. c, Third panel.") == ["a,","b,","c,"],"Alphabetical progression rejects backward inline references")
check(labels("Figure 2. a, First panel. b, Second panel. b, repeated inline label. c, Third panel.") == ["a,","b,","c,"],"Repeated single panel is not another heading")
print("5 alphabetical range-label checks passed")
check(labels("Figure 2. (a) First. (b–d) Combined. (d) Detail. (e) Last.") == ["(a)","(b–d)","(d)","(e)"],"Range can follow earlier single panel")

// Caption continuation uses original page geometry and the caption's style.
let pageBounds = CGRect(x:0,y:0,width:612,height:792)
func pageLine(_ text: String,_ y: CGFloat,_ x: CGFloat = 50,_ font: NSFont? = pdfCaptionFont) -> CaptionLine {
    CaptionLine(text:text,bounds:CGRect(x:x,y:y,width:230,height:12),font:font)
}
func captionPage(_ lines: [CaptionLine]) -> CaptionDetector.Page { CaptionDetector.Page(lines:lines,bounds:pageBounds) }
let firstCaptionPage = captionPage([pageLine("Figure 2. (A) First panel.",90),pageLine("(B) Second panel.",74)])
let continuedPage = captionPage([pageLine("(C) Third panel.",700),pageLine("Final caption explanation.",684)])
let pageCaption = CaptionDetector.captions(across:[firstCaptionPage,continuedPage],figure:"2")
check(pageCaption.count == 1 && pageCaption[0].text.contains("Final caption explanation"),"Append next-page panel continuation")
check(pageCaption[0].page == 0,"Keep original figure page as navigation target")
check(labels(pageCaption[0].text) == ["(A)","(B)","(C)"],"Uppercase parenthesized panel headings stay bold and ordered")
check(labels("Figure 2. A. First panel. B. Second panel. C. Third panel.") == ["A.","B.","C."],"Uppercase dotted panel labels")
check(labels("Figure 2. a, First panel. b, Second panel.") == ["a,","b,"],"Lowercase comma labels retained")
let sentencePages = [captionPage([pageLine("Figure 2. Signal was measured across",80)]),captionPage([pageLine("all tested neurons.",700)])]
check(CaptionDetector.captions(across:sentencePages,figure:"2")[0].text.contains("across all tested neurons"),"Sentence continues across page break")
let sameFontBody = captionPage([pageLine("Unrelated body text uses the same font.",700)])
check(!CaptionDetector.captions(across:[firstCaptionPage,sameFontBody],figure:"2")[0].text.contains("Unrelated"),"Font alone never establishes continuation")
let differentFont = captionPage([pageLine("(C) Third panel.",700,50,NSFont(name:"Helvetica",size:12)!)])
check(!CaptionDetector.captions(across:[firstCaptionPage,differentFont],figure:"2")[0].text.contains("Third panel"),"Reject next-page font mismatch")
let wrongCase = captionPage([pageLine("(c) A different label convention.",700)])
check(!CaptionDetector.captions(across:[firstCaptionPage,wrongCase],figure:"2")[0].text.contains("different label"),"Learn uppercase/lowercase caption label style")
let nextFigure = captionPage([pageLine("Figure 3. A different caption.",700)])
check(!CaptionDetector.captions(across:[firstCaptionPage,nextFigure],figure:"2")[0].text.contains("Figure 3"),"Stop at next figure caption")
let nextSection = captionPage([pageLine("Discussion",720),pageLine("(C) Unrelated section content.",700)])
check(!CaptionDetector.captions(across:[firstCaptionPage,nextSection],figure:"2")[0].text.contains("Unrelated"),"Do not skip section heading to find a panel letter")
let explicitPage = captionPage([pageLine("Figure 2 (continued).",720,50,pdfLabelFont),pageLine("Continuation starts with a complete sentence.",704)])
let explicitCaption = CaptionDetector.captions(across:[firstCaptionPage,explicitPage],figure:"2")
check(explicitCaption.count == 1 && explicitCaption[0].text.contains("Continuation starts"),"Explicit continued caption with different header font")
check(!explicitCaption[0].text.contains("continued"),"Remove repeated continuation heading")
let repeatedHeader = pageLine("Journal name | 2026",750,50,pdfLabelFont)
let withHeaders = [captionPage([repeatedHeader]+firstCaptionPage.lines+[pageLine("12",15)]),captionPage([repeatedHeader]+continuedPage.lines+[pageLine("13",15)])]
let noHeader = CaptionDetector.captions(across:withHeaders,figure:"2")[0].text
check(noHeader.contains("Third panel") && !noHeader.contains("Journal name") && !noHeader.contains("13"),"Skip running headers and page numbers")
let thirdPage = captionPage([pageLine("(D) Fourth panel.",700)])
let longSecond = captionPage([pageLine("(C) Third panel.",700)]+stride(from:684,through:76,by:-16).map { pageLine("Caption description continues.",CGFloat($0)) })
check(CaptionDetector.captions(across:[firstCaptionPage,longSecond,thirdPage],figure:"2")[0].text.contains("Fourth panel"),"Caption can continue across more than two pages")
let styleBoundary = captionPage([pageLine("(C) Third panel.",700),pageLine("Larger article body should not be included.",684,50,pdfLabelFont)])
check(!CaptionDetector.captions(across:[firstCaptionPage,styleBoundary],figure:"2")[0].text.contains("Larger article"),"Stop continuation at body font change")
let startsMidPage = captionPage([pageLine("Figure 2. (A) First panel.",500),pageLine("(B) Second panel.",484)])
check(!CaptionDetector.captions(across:[startsMidPage,continuedPage],figure:"2")[0].text.contains("Third panel"),"No page jump from caption ending mid-page without continued heading")
print("17 cross-page caption checks passed")
let lowerCommaPages = [captionPage([pageLine("Figure 2. a, First panel.",90),pageLine("b, Second panel.",74)]),captionPage([pageLine("c, Third panel.",700)])]
check(CaptionDetector.captions(across:lowerCommaPages,figure:"2")[0].text.contains("c, Third"),"Learn lowercase comma style across pages")
let dottedPages = [captionPage([pageLine("Figure 2. A. First panel.",90),pageLine("B. Second panel.",74)]),captionPage([pageLine("C. Third panel.",700)])]
check(CaptionDetector.captions(across:dottedPages,figure:"2")[0].text.contains("C. Third"),"Learn uppercase dotted style across pages")
let noJumpOverBody = captionPage(firstCaptionPage.lines+[pageLine("Article prose below caption.",35)])
check(!CaptionDetector.captions(across:[noJumpOverBody,continuedPage],figure:"2")[0].text.contains("Third panel"),"Do not bridge over text below caption")
let notContinued = captionPage([pageLine("Figure 2 controls were used in a separate experiment.",700)])
check(!CaptionDetector.captions(across:[firstCaptionPage,notContinued],figure:"2")[0].text.contains("separate experiment"),"Do not treat controls as continued heading")

let multiPageData = NSMutableData()
let multiPageContext = CGContext(consumer:CGDataConsumer(data:multiPageData as CFMutableData)!,mediaBox:&box,nil)!
for lines in [[("Figure 2. (A) First panel.",90.0),("(B) Second panel.",74.0)],[("(C) Third panel.",700.0),("The caption finishes on this page.",684.0)]] {
    multiPageContext.beginPDFPage(nil)
    for (text,y) in lines {
        multiPageContext.textPosition = CGPoint(x:50,y:y)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,10,nil)])),multiPageContext)
    }
    multiPageContext.endPDFPage()
}
multiPageContext.closePDF()
let multiPageDocument = PDFDocument(data:multiPageData as Data)!
let integratedCaption = CaptionDetector.captions(in:multiPageDocument,figure:"2")
check(integratedCaption.count == 1 && integratedCaption[0].text.contains("finishes on this page"),"Actual multi-page PDF extraction includes continuation")
check(labels(integratedCaption[0].text) == ["(A)","(B)","(C)"],"Actual PDF preserves learned uppercase label formatting")
print("6 additional cross-page and PDF integration checks passed")
let articleFont = NSFont(name:"Times-Roman",size:12)!
let articleLines = (0..<8).map { pageLine("This is ordinary article body text establishing a larger text font and its usual layout.",CGFloat(700-$0*16),50,articleFont) }
let smallFontCaptionPage = captionPage(articleLines+[pageLine("Figure 2. A caption description ends here.",90),pageLine("Another caption sentence.",74)])
let fullSentenceContinuation = captionPage([pageLine("This full sentence continues the caption.",700),pageLine("The caption ends here.",684)])
check(CaptionDetector.captions(across:[smallFontCaptionPage,fullSentenceContinuation],figure:"2")[0].text.contains("full sentence continues"),"Distinct smaller caption font plus layout supports full-sentence continuation")
let combinedColumnsAndPages = captionPage([
    pageLine("Figure 2. (A) Left-column caption.",160),pageLine("Left-column explanation.",144),
    pageLine("(B) Right-column continuation.",160,320),pageLine("Caption reaches the page bottom.",144,320)
])
check(CaptionDetector.captions(across:[combinedColumnsAndPages,continuedPage],figure:"2")[0].text.contains("Third panel"),"Follow both column and page transitions in one caption")
print("2 font-profile and combined-layout checks passed")

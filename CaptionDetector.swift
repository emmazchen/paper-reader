import Foundation
import CoreGraphics
import AppKit
import PDFKit

struct CaptionLine {
    let text: String
    let bounds: CGRect
    var font: NSFont? = nil
}

struct CaptionDetector {
    static func formattedLabelRanges(_ text: String) -> [NSRange] {
        let unit = "(?:\\([a-zA-Z](?:\\s*[-–—]\\s*[a-zA-Z])?\\)|[a-zA-Z](?:\\s*[-–—]\\s*[a-zA-Z])?[),.]?)"
        let groupedUnit = "(?:\\([a-zA-Z](?:\\s*[-–—]\\s*[a-zA-Z])?\\)|[a-zA-Z](?:\\s*[-–—]\\s*[a-zA-Z])?[),.])"
        let regex = try! NSRegularExpression(pattern:"(?m)^• (" + unit + "(?:\\s*(?:and|&|,)?\\s+" + groupedUnit + ")*)(?=\\s|$)")
        return regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).map { $0.range(at:1) }
    }
    static func panelLabelRanges(_ text: String) -> [NSRange] {
        let full = NSRange(text.startIndex...,in:text)
        let source = text as NSString
        let explicit = try! NSRegularExpression(pattern:"(?<![\\p{L}\\p{N}])(?:\\([a-zA-Z]\\)|[a-zA-Z]\\))(?=[\\s,]|$)")
        // Parse ranges before individual letters, so the c in a–c cannot
        // become a separate heading. Preserve source offsets for formatting.
        let rangeRegex = try! NSRegularExpression(pattern:"(?<![\\p{L}\\p{N}])(?:\\([a-zA-Z]\\s*[-–—]\\s*[a-zA-Z]\\)|[a-zA-Z]\\s*[-–—]\\s*[a-zA-Z][),.]?)(?=[\\s,]|$)")
        let rangeLabels = rangeRegex.matches(in:text,range:full).map(\.range).filter { range in
            let letters = Array(source.substring(with:range).lowercased().unicodeScalars.filter { CharacterSet.lowercaseLetters.contains($0) })
            return letters.count == 2 && letters[0].value < letters[1].value
        }
        var ranges: [NSRange] = rangeLabels
        for match in explicit.matches(in:text,range:full) {
            let range = match.range
            if rangeLabels.contains(where:{ NSIntersectionRange($0,range).length > 0 }) { continue }
            let label = source.substring(with:range)
            let prefix = source.substring(to:range.location).trimmingCharacters(in:.whitespacesAndNewlines)
            let boundary = prefix.isEmpty || prefix.last.map { ".!?:|".contains($0) } == true
            var groupedWithHeading = false
            if let previous = ranges.filter({ NSMaxRange($0) <= range.location }).max(by:{ $0.location < $1.location }) {
                let gap = source.substring(with:NSRange(location:NSMaxRange(previous),length:range.location-NSMaxRange(previous))).trimmingCharacters(in:.whitespacesAndNewlines)
                groupedWithHeading = ["",",","and","&"].contains(gap)
            }
            if !label.hasPrefix("(") || boundary || groupedWithHeading { ranges.append(range) }
        }
        // Commas can occur mid-line. Bare letters must follow a sentence end.
        let weak = try! NSRegularExpression(pattern:"(?<![\\p{L}\\p{N}])([a-zA-Z][,.])(?=\\s)|(?:^|[.!?]\\s+)([a-zA-Z])(?=\\s)")
        let candidates = weak.matches(in:text,range:full).map { match -> (range:NSRange, letter:UInt32, style:String, boundary:Bool) in
            let range = match.range(at:1).location == NSNotFound ? match.range(at:2) : match.range(at:1)
            let label = source.substring(with:range)
            let preceding = source.substring(to:range.location).trimmingCharacters(in:.whitespacesAndNewlines)
            return (range,label.lowercased().unicodeScalars.first!.value,(label.hasSuffix(",") ? "comma" : label.hasSuffix(".") ? "dot" : "bare") + (label.first!.isUppercase ? "upper" : "lower"),preceding.isEmpty || ".!?".contains(preceding.last!))
        }
        // Require an ascending pair in the same style, with at least one
        // boundary such as ". b," or ". c". A lone article "a" stays intact.
        for (index,item) in candidates.enumerated() {
            let paired = candidates.enumerated().contains { otherIndex, other in
                guard index != otherIndex, item.style == other.style, item.boundary || other.boundary else { return false }
                return (other.range.location < item.range.location && other.letter+1 == item.letter)
                    || (other.range.location > item.range.location && item.letter+1 == other.letter)
            }
            if paired && !rangeLabels.contains(where:{ NSIntersectionRange($0,item.range).length > 0 }) { ranges.append(item.range) }
        }
        let ordered = ranges.sorted { $0.location < $1.location }
        var grouped: [NSRange] = []
        for range in ordered {
            if let previous = grouped.last {
                let gap = source.substring(with:NSRange(location:NSMaxRange(previous),length:range.location-NSMaxRange(previous))).trimmingCharacters(in:.whitespacesAndNewlines)
                if ["",",","and","&"].contains(gap) {
                    grouped[grouped.count-1] = NSUnionRange(previous,range)
                    continue
                }
            }
            grouped.append(range)
        }
        // Caption descriptions progress alphabetically. A range establishes
        // coverage, while later descriptions may elaborate its panels (a–c,
        // then c,). Backward references inside prose are not new headings.
        var headings: [NSRange] = []
        var lastStart: UInt32?
        var coveredThrough: UInt32?
        for range in grouped {
            let label = source.substring(with:range)
            let letterRegex = try! NSRegularExpression(pattern:"(?<![a-zA-Z])[a-zA-Z](?![a-zA-Z])")
            let letters = letterRegex.matches(in:label,range:NSRange(label.startIndex...,in:label)).map {
                (label as NSString).substring(with:$0.range).lowercased().unicodeScalars.first!.value
            }
            guard let start = letters.first, let end = letters.last else { continue }
            let prefix = source.substring(to:range.location).trimmingCharacters(in:.whitespacesAndNewlines)
            let boundary = prefix.isEmpty || prefix.last.map { ".!?:|".contains($0) } == true
            if let previous = lastStart {
                guard start > previous || (start == previous && (coveredThrough ?? start) > start && boundary) else { continue }
            }
            headings.append(range)
            lastStart = start
            coveredThrough = max(coveredThrough ?? end,end)
        }
        return headings
    }
    static func format(_ text: String) -> String {
        let normalized = FigureSearch.normalize(text).trimmingCharacters(in:.whitespacesAndNewlines)
        let result = NSMutableString(string:normalized)
        for range in panelLabelRanges(normalized).reversed() {
            let label = (normalized as NSString).substring(with:range)
            result.replaceCharacters(in:range,with:"\n\n• " + label)
        }
        return (result as String).trimmingCharacters(in:.whitespacesAndNewlines)
    }

    struct Page {
        var lines: [CaptionLine]
        var bounds: CGRect
    }
    private static func compatible(_ expected: NSFont?, _ actual: NSFont?) -> Bool {
        guard let expected, let actual else { return false }
        return (expected.familyName ?? expected.fontName) == (actual.familyName ?? actual.fontName)
            && abs(expected.pointSize-actual.pointSize) <= max(0.6,expected.pointSize*0.10)
    }
    private static func signature(_ label: String) -> (first:UInt32,last:UInt32,style:String)? {
        let regex = try! NSRegularExpression(pattern:"(?<![\\p{L}])[a-zA-Z](?![\\p{L}])")
        let matches = regex.matches(in:label,range:NSRange(label.startIndex...,in:label))
        let values = matches.map { (label as NSString).substring(with:$0.range).lowercased().unicodeScalars.first!.value }
        guard let first = values.first, let last = values.last else { return nil }
        let style = (label.hasPrefix("(") ? "parentheses" : label.hasSuffix(",") ? "comma" : label.hasSuffix(".") ? "dot" : label.hasSuffix(")") ? "close" : "bare")
            + (label.first(where:{ $0.isLetter })?.isUppercase == true ? "Upper" : "Lower")
        return (first,last,style)
    }
    private static func headLabel(_ text: String) -> String? {
        let regex = try! NSRegularExpression(pattern:"^\\s*(\\([a-zA-Z](?:\\s*[-–—]\\s*[a-zA-Z])?\\)|[a-zA-Z](?:\\s*[-–—]\\s*[a-zA-Z])?[),.]?)(?=\\s|$)")
        guard let hit = regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
        return (text as NSString).substring(with:hit.range(at:1))
    }
    static func captions(in document: PDFDocument, figure: String) -> [(page:Int,text:String,font:NSFont?)] {
        let pages = (0..<document.pageCount).compactMap { index -> Page? in
            guard let page = document.page(at:index) else { return nil }
            let text = page.string ?? ""
            let lines = page.selection(for:NSRange(location:0,length:(text as NSString).length))?.selectionsByLine().compactMap { selection -> CaptionLine? in
                guard let text = selection.string, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
                return CaptionLine(text:text,bounds:selection.bounds(for:page),font:sourceFont(in:selection.attributedString))
            } ?? []
            return Page(lines:lines,bounds:page.bounds(for:.cropBox))
        }
        return captions(across:pages,figure:figure)
    }
    static func captions(across pages: [Page], figure: String) -> [(page:Int,text:String,font:NSFont?)] {
        let main = String(figure.prefix { $0.isNumber })
        guard !main.isEmpty else { return [] }
        func marginal(_ line: CaptionLine, _ page: Page) -> Bool {
            line.bounds.maxY > page.bounds.maxY-65 || line.bounds.minY < page.bounds.minY+45
        }
        func headerKey(_ text: String) -> String {
            FigureSearch.normalize(text).lowercased().replacingOccurrences(of:"[0-9]+",with:"#",options:.regularExpression)
        }
        var marginalPages: [String:Set<Int>] = [:]
        for (index,page) in pages.enumerated() {
            for line in page.lines where marginal(line,page) {
                marginalPages[headerKey(line.text),default:[]].insert(index)
            }
        }
        // Do not interpret running headers, footers, or page numbers as caption text.
        let cleaned = pages.map { page -> Page in
            Page(lines:page.lines.filter { line in
                guard marginal(line,page) else { return true }
                let number = line.text.trimmingCharacters(in:.whitespacesAndNewlines).range(of:"^(?:[0-9]+|[ivxlcdm]+)$",options:[.regularExpression,.caseInsensitive]) != nil
                return !number && (marginalPages[headerKey(line.text)]?.count ?? 0) < 2
            },bounds:page.bounds)
        }
        var bodySizes: [CGFloat:Int] = [:]
        for page in cleaned {
            for line in page.lines {
                guard let font = line.font else { continue }
                let bucket = (font.pointSize*2).rounded()/2
                bodySizes[bucket,default:0] += line.text.count
            }
        }
        let articleFontSize = bodySizes.max { $0.value < $1.value }?.key
        let continuedRegex = try! NSRegularExpression(pattern:"(?i)^\\s*fig(?:ure)?\\.?\\s*" + NSRegularExpression.escapedPattern(for:main) + "(?![a-z0-9])\\s*(?:[|:.–—-]\\s*)?\\(?cont(?:inued|\\.)?(?![a-z])\\)?[.:|]?\\s*")
        func continued(_ text: String) -> NSRange? {
            continuedRegex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text))?.range
        }
        func boundary(_ text: String) -> Bool {
            text.range(of:"(?i)^\\s*(?:(?:fig(?:ure)?|table)\\.?\\s*[0-9]|(?:[0-9]+(?:\\.[0-9]+)*[.]?\\s+)?(?:references|introduction|methods|results|discussion|conclusions?|acknowledg(?:e)?ments)\\b)",options:.regularExpression) != nil
        }
        var output: [(page:Int,text:String,font:NSFont?)] = []
        var consumed = Set<String>()
        for origin in cleaned.indices {
            for initial in blocks(in:cleaned[origin].lines,figure:main) {
                let key = "\(origin):\(initial.start.bounds.minX):\(initial.start.bounds.maxY)"
                if consumed.contains(key) { continue }
                var block = initial
                var text = block.text
                var currentPage = origin
                // Every successful step advances one page; no arbitrary two-page cutoff.
                while block.canContinue && currentPage+1 < cleaned.count {
                    let nextPage = cleaned[currentPage+1]
                    let previousPage = cleaned[currentPage]
                    // Cross a page edge only after reaching the bottom caption area.
                    let textBelow = previousPage.lines.contains { line in
                        abs(line.bounds.minX-block.last.bounds.minX) < 25 && line.bounds.maxY < block.last.bounds.minY-2
                    }
                    let nearBottom = !textBelow && block.last.bounds.minY <= previousPage.bounds.minY+max(110,previousPage.bounds.height*0.20)
                    let labels = panelLabelRanges(text)
                    let prior = labels.last.flatMap { signature((text as NSString).substring(with:$0)) }
                    let tail = text.trimmingCharacters(in:.whitespacesAndNewlines)
                    let unfinished = tail.last.map { !".!?:".contains($0) } == true
                    let totalCharacters = block.used.reduce(0) { $0+$1.text.count }
                    let matchingCharacters = block.used.filter { compatible(block.font,$0.font) }.reduce(0) { $0+$1.text.count }
                    let distinctCaptionFont = block.font.map { font in
                        articleFontSize.map { $0 >= font.pointSize*1.15 } ?? false
                    } ?? false
                    let consistentProfile = block.used.count >= 2 && matchingCharacters >= Int(Double(totalCharacters)*0.7)
                    let columnWidth = block.used.map { $0.bounds.width }.max() ?? 0
                    var choice: (index:Int,line:CaptionLine,explicit:Bool)?
                    // Examine the first block in each column. Do not skip unrelated
                    // prose to find a coincidental panel letter deeper on the page.
                    let topLines = nextPage.lines.enumerated().filter { item in
                        let line = item.element
                        guard line.bounds.maxY >= nextPage.bounds.maxY-max(180,nextPage.bounds.height*0.22) else { return false }
                        return !nextPage.lines.contains { other in
                            abs(other.bounds.minX-line.bounds.minX) < 25 && other.bounds.minY > line.bounds.maxY+1
                        }
                    }.sorted {
                        if abs($0.element.bounds.minX-$1.element.bounds.minX) > 25 { return $0.element.bounds.minX < $1.element.bounds.minX }
                        return $0.element.bounds.maxY > $1.element.bounds.maxY
                    }
                    for item in topLines {
                        let line = item.element
                        let explicit = continued(line.text) != nil
                        if !explicit && boundary(line.text) { continue }
                        let candidateHead = headLabel(line.text).flatMap(signature)
                        let panelContinues: Bool
                        if let prior, let next = candidateHead {
                            panelContinues = prior.style == next.style && (next.first == prior.last+1 || (prior.last > prior.first && next.first >= prior.first && next.first <= prior.last))
                        } else { panelContinues = false }
                        let beginsLower = line.text.trimmingCharacters(in:.whitespacesAndNewlines).first?.isLowercase == true
                        let sameStyle = compatible(block.font,line.font)
                            && abs(block.last.bounds.height-line.bounds.height) <= max(3,block.last.bounds.height*0.3)
                        let matchingColumn = columnWidth > 0 && line.bounds.width >= columnWidth*0.65 && line.bounds.width <= columnWidth*1.4
                        // Ordinary font matches need a linguistic cue. A reliably
                        // smaller caption font can also match a full new sentence,
                        // but only with a consistent profile and matching column.
                        let distinctBlock = distinctCaptionFont && consistentProfile && matchingColumn
                        if explicit || (nearBottom && sameStyle && (panelContinues || (unfinished && beginsLower) || distinctBlock)) {
                            choice = (item.offset,line,explicit); break
                        }
                    }
                    guard let choice else { break }
                    var lines = nextPage.lines
                    let marker = "Figure \(main). "
                    var firstText = choice.line.text
                    if choice.explicit, let range = continued(firstText) {
                        firstText = (firstText as NSString).replacingCharacters(in:range,with:"")
                    }
                    lines[choice.index] = CaptionLine(text:marker+firstText,bounds:choice.line.bounds,font:choice.line.font)
                    // Restrict the continuation to the learned caption body font.
                    guard var nextBlock = blocks(in:lines,figure:main,requiredFont:block.font).first(where:{ $0.start.bounds == choice.line.bounds }) else { break }
                    if nextBlock.text.hasPrefix(marker) { nextBlock.text.removeFirst(marker.count) }
                    nextBlock.text = nextBlock.text.trimmingCharacters(in:.whitespacesAndNewlines)
                    guard !nextBlock.text.isEmpty else { break }
                    currentPage += 1
                    consumed.insert("\(currentPage):\(choice.line.bounds.minX):\(choice.line.bounds.maxY)")
                    text = FigureSearch.normalize(text+"\n"+nextBlock.text)
                    nextBlock.font = block.font ?? nextBlock.font
                    block = nextBlock
                }
                output.append((origin,text,initial.font))
            }
        }
        return output
    }

    static func sourceFont(in text: NSAttributedString?) -> NSFont? {
        guard let text else { return nil }
        var fonts: [String:(font:NSFont,weight:Int)] = [:]
        text.enumerateAttribute(.font,in:NSRange(location:0,length:text.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            fonts[font.fontName] = (font,(fonts[font.fontName]?.weight ?? 0)+range.length)
        }
        return fonts.values.max { $0.weight < $1.weight }?.font
    }
    static func captionFont() -> NSFont {
        NSFontManager.shared.font(withFamily:"Merriweather",traits:[],weight:5,size:15)
            ?? NSFont(name:"Georgia",size:15)
            ?? NSFont.systemFont(ofSize:15)
    }
    static func display(_ text: String, font: NSFont?) -> NSAttributedString {
        let formatted = format(text)
        let manager = NSFontManager.shared
        let body = captionFont()
        let styled = NSMutableAttributedString(string:formatted,attributes:[.font:body,.foregroundColor:NSColor.black])
        for range in formattedLabelRanges(formatted) {
            styled.addAttribute(.font,value:manager.convert(body,toHaveTrait:.boldFontMask),range:range)
        }
        return styled
    }
    static func captions(in lines: [CaptionLine], figure: String) -> [String] {
        captionsWithFonts(in:lines,figure:figure).map(\.text)
    }
    static func captionsWithFonts(in lines: [CaptionLine], figure: String) -> [(text:String,font:NSFont?)] {
        blocks(in:lines,figure:figure).map { ($0.text,$0.font) }
    }
    private struct Block {
        var text: String
        var font: NSFont?
        var used: [CaptionLine]
        var start: CaptionLine
        var last: CaptionLine
        var canContinue: Bool
    }
    private static func blocks(in lines: [CaptionLine], figure: String, requiredFont: NSFont? = nil) -> [Block] {
        // A panel query such as 2b normally belongs to the caption for Figure 2.
        let main = String(figure.prefix { $0.isNumber })
        guard !main.isEmpty else { return [] }
        let label = "(?i)^\\s*(?:fig(?:ure)?\\.?)\\s*" + NSRegularExpression.escapedPattern(for:main) + "(?![0-9a-z])(?:\\s*[.:|–—-]\\s*|\\s+|$)"
        guard let regex = try? NSRegularExpression(pattern:label) else { return [] }
        func isStart(_ text: String) -> Bool {
            regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) != nil
        }
        func isOtherBlock(_ text: String) -> Bool {
            text.range(of:"(?i)^\\s*(?:(?:fig(?:ure)?|table)\\.?\\s*[0-9]|(?:[0-9]+[.]?\\s+)?(?:references|introduction|methods|results|discussion|conclusion)\\b)",options:.regularExpression) != nil
        }
        var results: [Block] = []
        for (index,first) in lines.enumerated() {
            var used: Set<Int> = [index]
            var fragments = [first.text]
            var last = first
            // Handle a separate label line, e.g. "Figure" then "2: ...".
            if first.text.trimmingCharacters(in:.whitespacesAndNewlines).range(of:"(?i)^fig(?:ure)?\\.?$",options:.regularExpression) != nil {
                let below = lines.enumerated().filter { !used.contains($0.offset) && abs($0.element.bounds.minX-first.bounds.minX) < 25 && first.bounds.minY-$0.element.bounds.maxY >= -2 && first.bounds.minY-$0.element.bounds.maxY < first.bounds.height*2 }
                    .min { $0.element.bounds.maxY > $1.element.bounds.maxY }
                if let below { fragments.append(below.element.text); used.insert(below.offset); last = below.element }
            }
            guard isStart(fragments.joined(separator:" ")) else { continue }
            var columnStart = first
            var canContinue = true
            // Follow a column downward; only when it runs out, inspect the
            // next column for a matching caption block in reading order.
            for _ in 0..<180 {
                let next = lines.enumerated().filter { item in
                    let line = item.element
                    let gap = last.bounds.minY-line.bounds.maxY
                    return !used.contains(item.offset) && gap >= -2 && gap <= max(last.bounds.height,line.bounds.height)*1.2 && abs(line.bounds.minX-columnStart.bounds.minX) <= 25 && line.bounds.minX < columnStart.bounds.maxX
                }.min { $0.element.bounds.maxY > $1.element.bounds.maxY }
                if let next {
                    guard !isOtherBlock(next.element.text), next.element.bounds.height <= max(columnStart.bounds.height,last.bounds.height)*1.45,
                          requiredFont == nil || compatible(requiredFont,next.element.font) else { canContinue = false; break }
                    used.insert(next.offset); last = next.element; fragments.append(last.text)
                    continue
                }
                let accumulated = fragments.joined(separator:" ")
                let priorLabels = panelLabelRanges(accumulated)
                let priorLetter = priorLabels.last.flatMap { range in
                    signature((accumulated as NSString).substring(with:range))?.last
                }
                let continuation = lines.enumerated().filter { item in
                    let line = item.element
                    guard !used.contains(item.offset),
                          line.bounds.minX >= columnStart.bounds.maxX+8,
                          abs(line.bounds.maxY-columnStart.bounds.maxY) <= max(line.bounds.height,columnStart.bounds.height)*1.5,
                          abs(line.bounds.height-last.bounds.height) <= max(3,last.bounds.height*0.3),
                          !isOtherBlock(line.text) else { return false }
                    // Only the top line of the block may start a continuation.
                    let hasLineAbove = lines.contains { other in
                        abs(other.bounds.minX-line.bounds.minX) <= 25 && other.bounds.minY >= line.bounds.maxY-2 && other.bounds.minY-line.bounds.maxY <= line.bounds.height*1.2
                    }
                    guard !hasLineAbove else { return false }
                    let fontMatches: Bool
                    if let leftFont = last.font, let rightFont = line.font {
                        fontMatches = leftFont.familyName == rightFont.familyName && abs(leftFont.pointSize-rightFont.pointSize) <= 1
                    } else { fontMatches = false }
                    let beginsNextPanel: Bool
                    let labelRegex = try! NSRegularExpression(pattern:"^\\s*\\(?([a-zA-Z])(?:[),.]|\\s)")
                    if let hit = labelRegex.firstMatch(in:line.text,range:NSRange(line.text.startIndex...,in:line.text)), let priorLetter {
                        let letter = (line.text as NSString).substring(with:hit.range(at:1)).lowercased().unicodeScalars.first!.value
                        beginsNextPanel = letter == priorLetter+1
                    } else { beginsNextPanel = false }
                    let tail = last.text.trimmingCharacters(in:.whitespacesAndNewlines)
                    let head = line.text.trimmingCharacters(in:.whitespacesAndNewlines)
                    let unfinished = tail.last.map { !".!?:".contains($0) } == true && head.first?.isLowercase == true
                    return (requiredFont == nil || compatible(requiredFont,line.font)) && (fontMatches || beginsNextPanel || unfinished)
                }.min { lhs,rhs in
                    if abs(lhs.element.bounds.minX-rhs.element.bounds.minX) > 25 { return lhs.element.bounds.minX < rhs.element.bounds.minX }
                    return lhs.element.bounds.maxY > rhs.element.bounds.maxY
                }
                guard let continuation else { break }
                columnStart = continuation.element
                last = continuation.element; used.insert(continuation.offset); fragments.append(last.text)
            }
            let result = FigureSearch.normalize(fragments.joined(separator:"\n")).trimmingCharacters(in:.whitespacesAndNewlines)
            if !results.contains(where: { $0.text == result }) {
                // Weight by text length so a short bold figure label does not
                // override the body font of the rest of the caption.
                var fonts: [String:(font:NSFont,weight:Int)] = [:]
                for index in used {
                    guard let font = lines[index].font else { continue }
                    fonts[font.fontName] = (font,(fonts[font.fontName]?.weight ?? 0)+lines[index].text.count)
                }
                results.append(Block(text:result,font:fonts.values.max { $0.weight < $1.weight }?.font,used:used.sorted().map { lines[$0] },start:first,last:last,canContinue:canContinue))
            }
        }
        return results
    }
}

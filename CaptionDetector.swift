import Foundation
import CoreGraphics
import AppKit

struct CaptionLine {
    let text: String
    let bounds: CGRect
    var font: NSFont? = nil
}

struct CaptionDetector {
    static func formattedLabelRanges(_ text: String) -> [NSRange] {
        let unit = "(?:\\([a-z]\\)|[a-z][),]?)"
        let groupedUnit = "(?:\\([a-z]\\)|[a-z][),])"
        let regex = try! NSRegularExpression(pattern:"(?m)^• (" + unit + "(?:\\s*(?:and|&|,)?\\s+" + groupedUnit + ")*)(?=\\s|$)")
        return regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).map { $0.range(at:1) }
    }
    static func panelLabelRanges(_ text: String) -> [NSRange] {
        let full = NSRange(text.startIndex...,in:text)
        let source = text as NSString
        let explicit = try! NSRegularExpression(pattern:"(?<![\\p{L}\\p{N}])(?:\\([a-z]\\)|[a-z]\\))(?=[\\s,]|$)")
        var ranges: [NSRange] = []
        for match in explicit.matches(in:text,range:full) {
            let range = match.range
            let label = source.substring(with:range)
            let prefix = source.substring(to:range.location).trimmingCharacters(in:.whitespacesAndNewlines)
            let boundary = prefix.isEmpty || prefix.last.map { ".!?:|".contains($0) } == true
            var groupedWithHeading = false
            if let previous = ranges.last {
                let gap = source.substring(with:NSRange(location:NSMaxRange(previous),length:range.location-NSMaxRange(previous))).trimmingCharacters(in:.whitespacesAndNewlines)
                groupedWithHeading = ["",",","and","&"].contains(gap)
            }
            if !label.hasPrefix("(") || boundary || groupedWithHeading { ranges.append(range) }
        }
        // Commas can occur mid-line. Bare letters must follow a sentence end.
        let weak = try! NSRegularExpression(pattern:"(?<![\\p{L}\\p{N}])([a-z],)(?=\\s)|(?:^|[.!?]\\s+)([a-z])(?=\\s)")
        let candidates = weak.matches(in:text,range:full).map { match -> (range:NSRange, letter:UInt32, comma:Bool, boundary:Bool) in
            let range = match.range(at:1).location == NSNotFound ? match.range(at:2) : match.range(at:1)
            let label = source.substring(with:range)
            let preceding = source.substring(to:range.location).trimmingCharacters(in:.whitespacesAndNewlines)
            return (range,label.unicodeScalars.first!.value,label.hasSuffix(","),preceding.isEmpty || ".!?".contains(preceding.last!))
        }
        // Require an ascending pair in the same style, with at least one
        // boundary such as ". b," or ". c". A lone article "a" stays intact.
        for (index,item) in candidates.enumerated() {
            let paired = candidates.enumerated().contains { otherIndex, other in
                guard index != otherIndex, item.comma == other.comma, item.boundary || other.boundary else { return false }
                return (other.range.location < item.range.location && other.letter+1 == item.letter)
                    || (other.range.location > item.range.location && item.letter+1 == other.letter)
            }
            if paired { ranges.append(item.range) }
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
        return grouped
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
        var results: [(text:String,font:NSFont?)] = []
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
            // Follow a column downward; only when it runs out, inspect the
            // next column for a matching caption block in reading order.
            for _ in 0..<180 {
                let next = lines.enumerated().filter { item in
                    let line = item.element
                    let gap = last.bounds.minY-line.bounds.maxY
                    return !used.contains(item.offset) && gap >= -2 && gap <= max(last.bounds.height,line.bounds.height)*1.2 && abs(line.bounds.minX-columnStart.bounds.minX) <= 25 && line.bounds.minX < columnStart.bounds.maxX
                }.min { $0.element.bounds.maxY > $1.element.bounds.maxY }
                if let next {
                    guard !isOtherBlock(next.element.text), next.element.bounds.height <= max(columnStart.bounds.height,last.bounds.height)*1.45 else { break }
                    used.insert(next.offset); last = next.element; fragments.append(last.text)
                    continue
                }
                let accumulated = fragments.joined(separator:" ")
                let priorLabels = panelLabelRanges(accumulated)
                let priorLetter = priorLabels.last.flatMap { range in
                    (accumulated as NSString).substring(with:range).unicodeScalars.first { CharacterSet.lowercaseLetters.contains($0) }?.value
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
                    let labelRegex = try! NSRegularExpression(pattern:"^\\s*\\(?([a-z])(?:[),]|\\s)")
                    if let hit = labelRegex.firstMatch(in:line.text,range:NSRange(line.text.startIndex...,in:line.text)), let priorLetter {
                        let letter = (line.text as NSString).substring(with:hit.range(at:1)).unicodeScalars.first!.value
                        beginsNextPanel = letter == priorLetter+1
                    } else { beginsNextPanel = false }
                    let tail = last.text.trimmingCharacters(in:.whitespacesAndNewlines)
                    let head = line.text.trimmingCharacters(in:.whitespacesAndNewlines)
                    let unfinished = tail.last.map { !".!?:".contains($0) } == true && head.first?.isLowercase == true
                    return fontMatches || beginsNextPanel || unfinished
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
                results.append((result,fonts.values.max { $0.weight < $1.weight }?.font))
            }
        }
        return results
    }
}

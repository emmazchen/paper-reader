import Foundation
import NaturalLanguage

struct FigureSearch {
    static func references(_ text: String) -> [(figure: String, range: NSRange)] {
        let regex = try! NSRegularExpression(pattern: "(?i)\\bfig(?:ure)?s?\\.?\\s*([0-9]+[a-z]?)(?![a-z0-9])")
        return regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).map {
            ((text as NSString).substring(with:$0.range(at:1)).lowercased(), $0.range)
        }
    }
    // Use ranges in the untouched PDF string: normalized offsets cannot map
    // reliably to PDFKit glyphs (line breaks, ligatures, and UTF-16 matter).
    static func mentionSentenceRanges(_ text: String, figure: String) -> [NSRange] {
        let hits = matches(text, figure: figure)
        guard !hits.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(NSRange(range, in: text)); return true
        }
        var result: [NSRange] = []
        for hit in hits {
            // Join tokens when a sentence tokenizer splits after "Fig.".
            let touching = sentences.filter { NSIntersectionRange($0, hit).length > 0 }
            let range = touching.reduce(hit) { NSUnionRange($0, $1) }
            if let last = result.last, NSIntersectionRange(last, range).length > 0 {
                result[result.count-1] = NSUnionRange(last, range)
            } else { result.append(range) }
        }
        return result
    }
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00ad}", with: "")
            .replacingOccurrences(of: "-\\s*\\n\\s*(?=[a-z])", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    static func query(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern = "^(?:fig(?:ure)?\\.?\\s*)?([0-9]+[a-z]?)$"
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)), let range = Range(match.range(at:1),in:text) else { return nil }
        return String(text[range])
    }
    static func matches(_ text: String, figure: String) -> [NSRange] {
        let escaped = NSRegularExpression.escapedPattern(for: figure)
        let suffix = figure.last?.isLetter == true ? "" : "[a-z]?"
        let pattern = "(?i)\\bfig(?:ure)?s?\\.?\\s*" + escaped + suffix + "(?![a-z0-9])"
        let regex = try! NSRegularExpression(pattern:pattern)
        return regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).map(\.range)
    }
    static func sentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in:text.startIndex..<text.endIndex) { range,_ in
            result.append(String(text[range])); return true
        }
        return result
    }
}

// Document-wide, frequency-based hints rather than a fixed list of figure types.
struct FigureTypes {
    let counts: [String:Int]
    private static let stop: Set<String> = ["a","an","the","in","on","of","to","and","or","as","at","by","for","from","with","see","also","shown","show","shows","described","illustrated","using","our","this","that","is","are","was","were","than","both","respectively","refer","references","result","results","compare","compared"]

    static func candidates(before range: NSRange, in text: String) -> [String] {
        let source = text as NSString
        let start = max(0,range.location-100)
        let prefix = source.substring(with:NSRange(location:start,length:range.location-start))
        let regex = try! NSRegularExpression(pattern:"([\\p{L}]+(?:[ \\t\\r\\n-]+[\\p{L}]+){0,3})[ \\t\\r\\n-]*$")
        guard let hit = regex.firstMatch(in:prefix,range:NSRange(prefix.startIndex...,in:prefix)) else { return [] }
        let words = (prefix as NSString).substring(with:hit.range(at:1)).lowercased().split { $0.isWhitespace || $0 == "-" }.map(String.init)
        guard let last = words.last, !stop.contains(last) else { return [] }
        // Soft variants share a bucket, but still require >3 occurrences.
        if last.hasPrefix("suppl") { return ["supplemental"] }
        if words.count >= 2, last == "data", words[words.count-2].hasPrefix("extend") { return ["extended data"] }
        var tail: [String] = []
        for word in words.reversed().prefix(3) {
            if stop.contains(word) { break }
            tail.insert(word,at:0)
        }
        guard !tail.isEmpty else { return [] }
        return (1...tail.count).map { tail.suffix($0).joined(separator:" ") }
    }
    init(pages: [String]) {
        var frequencies: [String:Int] = [:]
        for text in pages {
            for ref in FigureSearch.references(text) {
                for candidate in Self.candidates(before:ref.range,in:text) {
                    frequencies[candidate,default:0] += 1
                }
            }
        }
        counts = frequencies.filter { $0.value > 3 }
    }
    func type(before range: NSRange, in text: String) -> String? {
        Self.candidates(before:range,in:text).reversed().first { counts[$0] != nil }
    }
    func highlightRange(for range: NSRange, in text: String) -> NSRange {
        guard let type = type(before:range,in:text) else { return range }
        let wordCount = type.split(separator:" ").count
        let source = text as NSString
        let start = max(0,range.location-100)
        let prefix = source.substring(with:NSRange(location:start,length:range.location-start))
        let words = try! NSRegularExpression(pattern:"[\\p{L}]+")
        let tokens = words.matches(in:prefix,range:NSRange(prefix.startIndex...,in:prefix))
        guard tokens.count >= wordCount else { return range }
        let prefixStart = start + tokens[tokens.count-wordCount].range.location
        return NSRange(location:prefixStart,length:NSMaxRange(range)-prefixStart)
    }
}

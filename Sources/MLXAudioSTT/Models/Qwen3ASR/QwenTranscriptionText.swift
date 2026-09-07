import Foundation

/// Interprets the leading Qwen response header without changing inference tokens.
enum QwenTranscriptionText {
    static func parse(
        _ decoded: String,
        forcedLanguage: String? = nil,
        isFinal: Bool = true,
        expectsHeader: Bool = false
    ) -> (language: String?, text: String) {
        let text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        if let forcedLanguage, !forcedLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // The prompt already contains the header; generated text is all dictation.
            return (forcedLanguage, text)
        }

        let prefix = "language "
        let marker = "<asr_text>"
        if text.hasPrefix(prefix), let boundary = text.range(of: marker) {
            let name = text[text.index(text.startIndex, offsetBy: prefix.count)..<boundary.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let transcript = text[boundary.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (name.isEmpty ? nil : name, transcript)
        }

        if (!isFinal || expectsHeader) && (prefix.hasPrefix(text) || text.hasPrefix(prefix)) {
            // Header tokens can straddle both decode passes and confirmation boundaries.
            return (nil, "")
        }
        if text.hasPrefix(prefix), let start = text.firstIndex(of: "<"),
           marker.hasPrefix(String(text[start...])) {
            return (nil, "")
        }
        // Preserve the batch fallback for ordinary dictation without a protocol header.
        return (nil, text)
    }

    static func display(
        completed: String = "",
        confirmed: String,
        fullWindow: String,
        forcedLanguage: String?
    ) -> (confirmed: String, provisional: String) {
        let stableWindow = parse(confirmed, forcedLanguage: forcedLanguage, isFinal: false).text
        let fullWindow = parse(fullWindow, forcedLanguage: forcedLanguage, isFinal: false).text
        let stable = concatText(completed, stableWindow)
        let full = concatText(completed, fullWindow)
        // Joining the whole window first preserves separators and overlap handling.
        let prefix = full.hasPrefix(stable) ? stable : completed
        return (prefix, String(full.dropFirst(prefix.count)))
    }

    static func appendText(_ segment: String, to base: inout String) {
        let normalizedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSegment.isEmpty else { return }
        if base.isEmpty {
            base = normalizedSegment
            return
        }
        let dedupedSegment = dedupeLeadingWordOverlap(base: base, segment: normalizedSegment)
        let containedTrimmedSegment = trimContainedLeadingOverlap(base: base, segment: dedupedSegment)
        guard !containedTrimmedSegment.isEmpty else { return }
        if shouldSkipDuplicateAppend(base: base, segment: containedTrimmedSegment) {
            return
        }
        if base.last?.isWhitespace == true || containedTrimmedSegment.first?.isWhitespace == true {
            base += containedTrimmedSegment
        } else {
            base += " " + containedTrimmedSegment
        }
    }

    private static func normalizedComparableWord(_ word: String) -> String {
        let asciiApostrophe: UnicodeScalar = "'"
        let smartApostrophe: UnicodeScalar = "’"
        let normalizedScalars = word.lowercased().unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) ||
                scalar == asciiApostrophe ||
                scalar == smartApostrophe
        }
        return String(String.UnicodeScalarView(normalizedScalars))
    }

    private static func wordsEquivalent(
        lhsRaw: String,
        lhsNormalized: String,
        rhsRaw: String,
        rhsNormalized: String
    ) -> Bool {
        if !lhsNormalized.isEmpty && !rhsNormalized.isEmpty {
            return lhsNormalized == rhsNormalized
        }
        return lhsRaw.caseInsensitiveCompare(rhsRaw) == .orderedSame
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { normalizedComparableWord(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func shouldSkipDuplicateAppend(base: String, segment: String) -> Bool {
        let segmentWords = normalizedWords(segment)
        guard !segmentWords.isEmpty else { return true }

        let baseWords = normalizedWords(base)
        guard !baseWords.isEmpty else { return false }

        if baseWords.count < segmentWords.count { return false }
        let lookbackCount = min(baseWords.count, max(segmentWords.count * 2, 48))
        let tailWords = Array(baseWords.suffix(lookbackCount))
        guard tailWords.count >= segmentWords.count else { return false }

        let tailSuffix = Array(tailWords.suffix(segmentWords.count))
        return tailSuffix == segmentWords
    }

    private static func containsContiguousSubsequence(
        haystack: [String],
        needle: [String]
    ) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        let maxStart = haystack.count - needle.count
        if maxStart < 0 { return false }

        for start in 0...maxStart {
            var matches = true
            for idx in 0..<needle.count where haystack[start + idx] != needle[idx] {
                matches = false
                break
            }
            if matches {
                return true
            }
        }

        return false
    }

    private static func trimContainedLeadingOverlap(base: String, segment: String) -> String {
        let segmentRawWords = segment.split(whereSeparator: \.isWhitespace).map(String.init)
        guard segmentRawWords.count >= 8 else { return segment }

        let baseWords = normalizedWords(base)
        guard !baseWords.isEmpty else { return segment }

        let segmentWords = segmentRawWords.map { normalizedComparableWord($0) }
        let lookbackCount = min(baseWords.count, max(segmentWords.count * 4, 160))
        let tailWords = Array(baseWords.suffix(lookbackCount))
        guard !tailWords.isEmpty else { return segment }

        let minOverlapWords = min(12, segmentWords.count)
        guard minOverlapWords >= 8 else { return segment }

        for overlap in stride(from: segmentWords.count, through: minOverlapWords, by: -1) {
            let prefix = Array(segmentWords.prefix(overlap))
            if containsContiguousSubsequence(haystack: tailWords, needle: prefix) {
                let remainder = segmentRawWords.dropFirst(overlap)
                return remainder.joined(separator: " ")
            }
        }

        return segment
    }

    private static func dedupeLeadingWordOverlap(base: String, segment: String, maxWords: Int = 64) -> String {
        let baseWords = base.split(whereSeparator: \.isWhitespace).map(String.init)
        let segmentWords = segment.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !baseWords.isEmpty, !segmentWords.isEmpty else { return segment }
        let baseWordsNormalized = baseWords.map { normalizedComparableWord($0) }
        let segmentWordsNormalized = segmentWords.map { normalizedComparableWord($0) }

        let maxOverlap = min(maxWords, min(baseWords.count, segmentWords.count))
        var overlapCount = 0

        if maxOverlap > 0 {
            for size in stride(from: maxOverlap, through: 1, by: -1) {
                var matches = true
                for idx in 0..<size {
                    let lhsIdx = baseWords.count - size + idx
                    if !wordsEquivalent(
                        lhsRaw: baseWords[lhsIdx],
                        lhsNormalized: baseWordsNormalized[lhsIdx],
                        rhsRaw: segmentWords[idx],
                        rhsNormalized: segmentWordsNormalized[idx]
                    ) {
                        matches = false
                        break
                    }
                }
                if matches {
                    overlapCount = size
                    break
                }
            }
        }

        guard overlapCount > 0 else { return segment }
        let remainder = segmentWords.dropFirst(overlapCount)
        return remainder.joined(separator: " ")
    }

    static func concatText(_ a: String, _ b: String) -> String {
        var result = a
        appendText(b, to: &result)
        return result
    }

}

//
//  TranscriptFormatter.swift
//  Ramble
//

import Foundation

/// Groups a plain-text transcript into paragraphs.
///
/// Cloud transcripts arrive already broken up — Deepgram returns paragraphs
/// natively, Groq derives them from segment timings, and the proxy groups
/// sentences for models that hand back a single block. On-device transcription
/// has no equivalent, so a long voice memo reads as one unbroken wall of text.
/// This applies the same grouping locally, so a transcript looks the same
/// whichever model produced it.
///
/// Deliberately conservative: text that is short, already paragraphed, or has
/// no sentence boundaries to break on comes back unchanged. Thresholds mirror
/// `formatTextIntoParagraphs` in proxy/src/index.js — keep in sync.
enum TranscriptFormatter {
    /// Below this length a transcript reads fine as a single block.
    private static let minLength = 500

    /// Sentences accumulate until the paragraph reaches this length.
    private static let targetLength = 350

    /// A trailing remainder shorter than this joins the preceding paragraph
    /// rather than standing alone as a one-line orphan.
    private static let orphanLength = 80

    static func paragraphs(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLength else { return trimmed }

        // Already paragraphed — leave it alone.
        let existingBreak = trimmed.range(of: "\n[ \t]*\n", options: .regularExpression)
        guard existingBreak == nil else { return trimmed }

        let sentences = splitIntoSentences(trimmed)
        guard sentences.count > 1 else { return trimmed }

        var paragraphs: [String] = []
        var current = ""

        for sentence in sentences {
            current = current.isEmpty ? sentence : "\(current) \(sentence)"
            if current.count >= targetLength {
                paragraphs.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            if current.count < orphanLength, let last = paragraphs.popLast() {
                paragraphs.append("\(last) \(current)")
            } else {
                paragraphs.append(current)
            }
        }

        return paragraphs.joined(separator: "\n\n")
    }

    /// Sentence segmentation via Foundation, which handles abbreviations and
    /// non-Latin punctuation better than splitting on terminators by hand.
    private static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.bySentences, .localized]
        ) { substring, _, _, _ in
            guard let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sentence.isEmpty else { return }
            sentences.append(sentence)
        }
        return sentences
    }
}

extension TranscriptFormatter {
    /// Filler words the proxy strips server-side for cloud models. On-device
    /// transcription never went through the proxy, so the "Remove filler words"
    /// toggle did nothing for Apple Speech or local Whisper.
    ///
    /// Mirror of `FILLER_REGEX` in proxy/src/index.js: only the disfluencies most
    /// people want gone, not slang like "like" or "you know", which carries meaning.
    private static let fillerPattern = "\\b(?:um+|uh+|er+|ah+|hmm+|mhm+|uhm+|erm+)\\b[\\s,.;:!?]*"

    static func removingFillerWords(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: fillerPattern, options: [.caseInsensitive]) else {
            return text
        }
        let stripped = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )

        // Collapse the spaces the removal leaves behind without flattening
        // paragraph breaks, same as the proxy does.
        return stripped
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

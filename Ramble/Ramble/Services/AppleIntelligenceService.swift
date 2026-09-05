//
//  AppleIntelligenceService.swift
//  Ramble
//

import FoundationModels
import Foundation

/// One term the transcript got wrong, and the dictionary entry it should be.
@available(iOS 26.0, *)
@Generable
struct VocabularyCorrection {
    @Guide(description: "The exact wrong text as it appears in the transcript")
    var heard: String
    @Guide(description: "The dictionary term it should be, copied exactly")
    var correct: String
}

@available(iOS 26.0, *)
@Generable
struct VocabularyCorrectionPlan {
    @Guide(description: "Only clear mishearings of the listed terms. Empty if the transcript already spells them correctly.")
    var corrections: [VocabularyCorrection]
}

/// Apple's on-device language model, used for one job: correcting dictionary
/// terms the speech recogniser misheard.
///
/// It was also used to merge over-split speaker labels. That was removed: on a
/// real recording it merged two different people into one, and a wrong merge
/// destroys information that word-level attribution had got right.
@MainActor
enum AppleIntelligenceService {

    enum Unavailable: String {
        case notSupported = "on-device model needs iOS 26"
        case deviceNotEligible = "device doesn't support Apple Intelligence"
        case appleIntelligenceNotEnabled = "Apple Intelligence is off in Settings"
        case modelNotReady = "on-device model isn't downloaded yet"
    }

    static func unavailableReason() -> Unavailable? {
        guard #available(iOS 26.0, *) else { return .notSupported }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        @unknown default:
            return .modelNotReady
        }
    }

    /// End-to-end check that the on-device model actually answers, using the same
    /// guided-generation path the real features use. Availability reporting
    /// `available` is not proof the model responds, and "proposed nothing" looks
    /// identical to "never ran", so this exists to tell them apart.
    static func selfTest() async -> String {
        if let reason = unavailableReason() { return "Unavailable: \(reason.rawValue)" }
        guard #available(iOS 26.0, *) else { return "Unavailable: needs iOS 26" }

        let session = LanguageModelSession(
            instructions: "A speech recogniser wrote this transcript without knowing the listed terms."
        )
        let prompt = """
        Terms:
        - Ramble

        Transcript:
        i opened rumble and started talking
        """

        let started = Date()
        do {
            let response = try await session.respond(to: prompt, generating: VocabularyCorrectionPlan.self)
            let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
            let described = response.content.corrections
                .map { "\($0.heard) to \($0.correct)" }
                .joined(separator: ", ")
            return response.content.corrections.isEmpty
                ? "Answered in \(elapsed)s, proposed nothing"
                : "Answered in \(elapsed)s: \(described)"
        } catch {
            return "Failed: \(error.localizedDescription)"
        }
    }

}

// MARK: - Dictionary corrections

@MainActor
extension AppleIntelligenceService {
    /// Ask the on-device model which dictionary terms the transcript misheard.
    ///
    /// This is the safe way to use a dictionary with local Whisper. Feeding terms
    /// to the decoder as a prompt truncated transcripts and garbled other
    /// languages; a plain find-and-replace can only fix casing. A model can spot
    /// "rumble" where you said "Ramble", and because every proposal is validated
    /// against the dictionary before anything is replaced, the worst case is a
    /// substitution that was already possible by hand.
    static func vocabularyCorrections(in text: String, terms: String) async -> [(heard: String, correct: String)] {
        guard #available(iOS 26.0, *) else { return [] }
        guard unavailableReason() == nil else { return [] }

        let dictionary = terms
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
        guard !dictionary.isEmpty, !text.isEmpty else { return [] }

        let session = LanguageModelSession(instructions: """
        A speech recogniser produced a transcript without knowing these terms, so         it may have written them as similar-sounding words.

        Find only those mishearings. Report the exact wrong text and which term it         should be. Do not correct grammar, punctuation, or anything else, and do         not report a term that is already written correctly. If nothing was         misheard, return no corrections.
        """)

        let prompt = """
        Terms:
        \(dictionary.map { "- \($0)" }.joined(separator: "\n"))

        Transcript:
        \(text.count > 4000 ? String(text.prefix(4000)) : text)
        """

        do {
            let response = try await session.respond(to: prompt, generating: VocabularyCorrectionPlan.self)
            // Validated, not trusted: the replacement must be a dictionary term and
            // the text it replaces must actually be in the transcript.
            return response.content.corrections.compactMap { correction in
                let heard = correction.heard.trimmingCharacters(in: .whitespacesAndNewlines)
                let correct = correction.correct.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !heard.isEmpty,
                      dictionary.contains(where: { $0.caseInsensitiveCompare(correct) == .orderedSame }),
                      heard.caseInsensitiveCompare(correct) != .orderedSame,
                      text.range(of: heard, options: .caseInsensitive) != nil
                else { return nil }
                return (heard: heard, correct: correct)
            }
        } catch {
            print("[VocabularyCorrection] \(error.localizedDescription)")
            return []
        }
    }
}

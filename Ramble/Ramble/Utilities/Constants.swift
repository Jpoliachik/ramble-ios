//
//  Constants.swift
//  Ramble
//

import Foundation

enum Constants {
    static let groqAPIEndpoint = "https://api.groq.com/openai/v1/audio/transcriptions"
    static let groqModel = "whisper-large-v3-turbo"

    // Cost tracking: ~$0.04 per hour of audio
    static let costPerHour: Double = 0.04

    enum AudioSettings {
        static let sampleRate: Double = 16000
        static let numberOfChannels: Int = 1
    }
}

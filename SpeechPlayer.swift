import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
final class SpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentCharacter = 0
    @Published private(set) var totalCharacters = 0
    @Published var selectedVoiceIdentifier: String
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var pitch: Float = 1.0

    let voices: [AVSpeechSynthesisVoice]
    private let synthesizer = AVSpeechSynthesizer()
    private var chunks: [SpeechChunk] = []
    private var nextChunk = 0
    private var generation = 0
    private var utteranceInfo: [ObjectIdentifier: UtteranceInfo] = [:]

    override init() {
        let available = AVSpeechSynthesisVoice.speechVoices().sorted {
            ($0.language, $0.name) < ($1.language, $1.name)
        }
        voices = available
        selectedVoiceIdentifier = available.first(where: { $0.language.hasPrefix("en") })?.identifier
            ?? available.first?.identifier ?? ""
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
        configureRemoteCommands()
    }

    func play(text: String, from position: Int = 0) {
        // Invalidate callbacks from any utterance being stopped before starting a new run.
        generation += 1
        synthesizer.stopSpeaking(at: .immediate)
        utteranceInfo.removeAll()
        chunks = Self.makeChunks(text, maximumLength: 650)
        totalCharacters = (text as NSString).length
        currentCharacter = min(max(position, 0), totalCharacters)
        nextChunk = chunks.firstIndex(where: { NSMaxRange($0.range) > currentCharacter }) ?? chunks.count
        isSpeaking = false
        isPaused = false
        speakNext()
    }

    func pause() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        isPaused = true
        isSpeaking = false
        updateNowPlaying()
    }

    func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            isSpeaking = true
            updateNowPlaying()
        } else if nextChunk < chunks.count {
            speakNext()
        }
    }

    func stop() {
        generation += 1
        synthesizer.stopSpeaking(at: .immediate)
        utteranceInfo.removeAll()
        isSpeaking = false
        isPaused = false
        nextChunk = chunks.count
        updateNowPlaying()
    }

    private func speakNext() {
        guard nextChunk < chunks.count else {
            isSpeaking = false
            isPaused = false
            updateNowPlaying()
            return
        }

        let chunk = chunks[nextChunk]
        nextChunk += 1

        // If resuming in the middle of a chunk, start at the requested UTF-16 offset.
        let relativeStart = min(max(currentCharacter - chunk.range.location, 0), (chunk.text as NSString).length)
        let remainingLength = (chunk.text as NSString).length - relativeStart
        guard remainingLength > 0 else {
            speakNext()
            return
        }
        let spokenText = (chunk.text as NSString).substring(
            with: NSRange(location: relativeStart, length: remainingLength)
        )

        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = min(max(pitch, 0.5), 2.0)
        let baseOffset = chunk.range.location + relativeStart
        utteranceInfo[ObjectIdentifier(utterance)] = UtteranceInfo(offset: baseOffset, generation: generation)
        currentCharacter = max(currentCharacter, baseOffset)
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
        updateNowPlaying()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("ReadMeh audio session configuration failed: %@", error.localizedDescription)
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "ReadMeh",
            MPMediaItemPropertyArtist: "PDF narration",
            MPNowPlayingInfoPropertyPlaybackRate: isSpeaking ? 1.0 : 0.0
        ]
    }

    private static func makeChunks(_ text: String, maximumLength: Int) -> [SpeechChunk] {
        let source = text as NSString
        guard source.length > 0 else { return [] }
        var output: [SpeechChunk] = []
        var start = 0

        while start < source.length {
            var end = min(start + maximumLength, source.length)
            if end < source.length {
                // Prefer a nearby whitespace boundary, but never split off punctuation or drop text.
                let lowerBound = max(start + 1, end - 120)
                let searchRange = NSRange(location: lowerBound, length: source.length - lowerBound)
                let boundary = source.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards, range: searchRange)
                if boundary.location != NSNotFound && boundary.location > start {
                    end = NSMaxRange(boundary)
                }
            }
            if end <= start { end = min(start + maximumLength, source.length) }
            let range = NSRange(location: start, length: end - start)
            output.append(SpeechChunk(text: source.substring(with: range), range: range))
            start = end
        }
        return output
    }

    private func updateProgress(for utterance: AVSpeechUtterance, range: NSRange) {
        guard let info = utteranceInfo[ObjectIdentifier(utterance)], info.generation == generation else { return }
        currentCharacter = min(totalCharacters, info.offset + NSMaxRange(range))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in self.updateProgress(for: utterance, range: characterRange) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let key = ObjectIdentifier(utterance)
            guard let info = self.utteranceInfo.removeValue(forKey: key), info.generation == self.generation else { return }
            self.currentCharacter = max(self.currentCharacter, info.offset + (utterance.speechString as NSString).length)
            self.speakNext()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let key = ObjectIdentifier(utterance)
            guard let info = self.utteranceInfo.removeValue(forKey: key), info.generation == self.generation else { return }
            self.isSpeaking = false
        }
    }
}

private struct SpeechChunk {
    let text: String
    let range: NSRange
}

private struct UtteranceInfo {
    let offset: Int
    let generation: Int
}

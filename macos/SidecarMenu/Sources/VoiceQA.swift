import Foundation
import WhisperKit
import AVFoundation
import Accelerate

/// Orchestrates the voice Q&A pipeline: hold-to-talk → batch transcribe → search → answer.
@MainActor
final class VoiceQA: ObservableObject {
    static let shared = VoiceQA()

    enum State: Equatable {
        case idle
        case loading
        case listening
        case transcribing
        case searching
        case answering
        case done(answer: String, sources: [SearchResult], knowledgeBlocks: [String])
        case error(String)
    }

    @Published var state: State = .idle
    @Published var partialTranscription: String = ""
    @Published var bufferEnergy: [Float] = []
    @Published var modelReady = false
    @Published var injectedContext: String = ""
    @Published var pendingInput: String = ""
    @Published var focusTrigger: Int = 0

    var conversationHistory: [(question: String, answer: String, sources: [SearchResult], attachments: [URL])] = []
    @Published var referencedDocuments: [SearchResult] = []
    @Published var attachedFiles: [URL] = []
    private var questionQueue: [String] = []

    private var audioEngine: AVAudioEngine?
    private var audioSamples: [Float] = [] // 16kHz mono Float32 — what WhisperKit expects
    private let settings = SettingsManager.shared

    private init() {}

    // MARK: - Model Pre-loading (call at app launch)

    /// Pre-load the WhisperKit model in the background so it's ready when needed.
    func preloadModel() {
        guard !modelReady else { return }
        Task.detached(priority: .background) {
            let whisper = await WhisperManager.shared
            let model = await whisper.loadedModel
            if model != nil, await whisper.whisperKit != nil {
                await MainActor.run { self.modelReady = true }
                Logger.log("Voice Q&A: model already loaded", source: "VoiceQA")
                return
            }
            do {
                let modelName = await self.settings.whisperModel
                Logger.log("Voice Q&A: pre-loading model \(modelName)", source: "VoiceQA")
                try await whisper.loadModel(modelName)
                await MainActor.run { self.modelReady = true }
                Logger.log("Voice Q&A: model pre-loaded", source: "VoiceQA")
            } catch {
                Logger.log("Voice Q&A: pre-load failed: \(error)", source: "VoiceQA")
            }
        }
    }

    // MARK: - Hold-to-Talk

    func startRecording() {
        switch state {
        case .idle, .error:
            beginRecording()
        case .done:
            beginRecording()
        default:
            break // Already recording/processing, ignore
        }
    }

    func stopRecording() {
        guard case .listening = state else { return }
        finishRecording()
    }

    /// Attachments captured at submit time, used by processQuestion
    private var currentAttachments: [URL] = []

    func submitTextQuestion(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        // Queue if currently processing
        switch state {
        case .searching, .answering, .transcribing, .loading:
            questionQueue.append(question)
            Logger.log("Voice Q&A: queued question (\(questionQueue.count) in queue)", source: "VoiceQA")
            return
        default:
            break
        }

        // Capture and clear attached files at submit time
        currentAttachments = attachedFiles
        attachedFiles = []

        partialTranscription = question
        processQuestion(question)
    }

    // MARK: - Recording (16kHz mono Float32 — matches WhisperKit's expected format)

    private func beginRecording() {
        state = .loading
        partialTranscription = ""
        bufferEnergy = []
        audioSamples = []

        Task {
            // Ensure model is ready
            if !modelReady {
                partialTranscription = "Loading model..."
                do {
                    try await WhisperManager.shared.loadModel(settings.whisperModel)
                    modelReady = true
                } catch {
                    state = .error("Model failed: \(error.localizedDescription)")
                    return
                }
            }

            guard case .loading = state else { return }

            do {
                let engine = AVAudioEngine()
                let inputNode = engine.inputNode
                let hwFormat = inputNode.outputFormat(forBus: 0)

                // Target format: 16kHz mono Float32 (what Whisper expects natively)
                guard let targetFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 16000,
                    channels: 1,
                    interleaved: false
                ) else {
                    state = .error("Failed to create audio format")
                    return
                }

                // Converter from hardware format → 16kHz mono
                guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
                    state = .error("Failed to create audio converter")
                    return
                }

                inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
                    guard let self = self else { return }

                    // Convert to 16kHz mono Float32
                    let ratio = 16000.0 / hwFormat.sampleRate
                    let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                    guard let outputBuffer = AVAudioPCMBuffer(
                        pcmFormat: targetFormat,
                        frameCapacity: outputFrameCount
                    ) else { return }

                    var error: NSError?
                    converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                        outStatus.pointee = .haveData
                        return buffer
                    }

                    if let channelData = outputBuffer.floatChannelData?[0] {
                        let count = Int(outputBuffer.frameLength)
                        let samples = Array(UnsafeBufferPointer(start: channelData, count: count))

                        // Compute energy for visualization
                        var rms: Float = 0
                        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(count))
                        let energy = min(rms * 8, 1.0)

                        DispatchQueue.main.async {
                            self.audioSamples.append(contentsOf: samples)
                            self.bufferEnergy.append(energy)
                            if self.bufferEnergy.count > 50 {
                                self.bufferEnergy.removeFirst()
                            }
                        }
                    }
                }

                engine.prepare()
                try engine.start()

                self.audioEngine = engine
                self.state = .listening
                Logger.log("Voice Q&A: recording (16kHz mono Float32)", source: "VoiceQA")
            } catch {
                Logger.log("Voice Q&A: mic error: \(error)", source: "VoiceQA")
                state = .error("Microphone error: \(error.localizedDescription)")
            }
        }
    }

    private func finishRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        let samples = audioSamples
        audioSamples = []

        guard !samples.isEmpty else {
            state = .error("No audio recorded")
            return
        }

        let durationSec = Float(samples.count) / 16000.0
        Logger.log("Voice Q&A: recorded \(String(format: "%.1f", durationSec))s (\(samples.count) samples)", source: "VoiceQA")

        state = .transcribing

        Task {
            do {
                guard let kit = WhisperManager.shared.whisperKit else {
                    state = .error("WhisperKit not loaded")
                    return
                }

                // Batch transcribe the raw Float32 samples — no file I/O, no resampling needed
                let results = try await kit.transcribe(
                    audioArray: samples,
                    decodeOptions: DecodingOptions(
                        task: .transcribe,
                        language: "en",
                        temperature: 0.0,
                        temperatureFallbackCount: 3,
                        compressionRatioThreshold: 2.4,
                        logProbThreshold: -1.0,
                        noSpeechThreshold: 0.6
                    )
                )

                let text = results.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                Logger.log("Voice Q&A: transcribed: \"\(text)\"", source: "VoiceQA")

                guard !text.isEmpty else {
                    state = .error("No speech detected. Hold the hotkey while speaking.")
                    return
                }

                partialTranscription = text
                processQuestion(text)
            } catch {
                Logger.log("Voice Q&A: transcribe error: \(error)", source: "VoiceQA")
                state = .error("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Search + Answer

    private func processQuestion(_ question: String) {
        Logger.log("Voice Q&A: processQuestion: \(question)", source: "VoiceQA")
        state = .searching

        Task {
            do {
                // Build search conversation for smart search
                let searchConversation: String
                if !injectedContext.isEmpty {
                    let contextSnippet = String(injectedContext.suffix(2000))
                    searchConversation = contextSnippet + "\n\nUser question: " + question
                    Logger.log("Voice Q&A: searching with \(contextSnippet.count) chars of context", source: "VoiceQA")
                } else {
                    searchConversation = question
                }

                // Dual BM25 search: question keywords + context-enriched query
                Logger.log("Voice Q&A: BM25 search...", source: "VoiceQA")
                var bm25Results = try SidecarCLI.search(
                    query: question,
                    maxResults: settings.maxResults * 3,
                    cliPath: settings.cliPath
                )
                Logger.log("Voice Q&A: BM25 (question) returned \(bm25Results.count) results", source: "VoiceQA")

                // If we have context, also search with context to find topically relevant docs
                if !injectedContext.isEmpty {
                    let contextQuery = String(injectedContext.suffix(300)) + " " + question
                    let contextResults = try SidecarCLI.search(
                        query: contextQuery,
                        maxResults: settings.maxResults * 2,
                        cliPath: settings.cliPath
                    )
                    Logger.log("Voice Q&A: BM25 (context) returned \(contextResults.count) results", source: "VoiceQA")

                    // Merge: add context results that aren't already in question results
                    let existingFiles = Set(bm25Results.map(\.file))
                    for result in contextResults where !existingFiles.contains(result.file) {
                        bm25Results.append(result)
                    }
                }

                // NLEmbedding semantic re-rank (instant, on-device)
                var results = SemanticRanker.rerank(
                    query: question,
                    candidates: bm25Results,
                    topN: settings.maxResults
                )

                // Smart search refinement (async, AI-powered)
                if !results.isEmpty {
                    do {
                        let smartResults = try await SidecarCLI.smartSearch(
                            conversation: searchConversation,
                            maxResults: settings.maxResults,
                            cliPath: settings.cliPath
                        )
                        if !smartResults.isEmpty {
                            Logger.log("Voice Q&A: smart search refined to \(smartResults.count) results", source: "VoiceQA")
                            results = smartResults
                        }
                    } catch {
                        Logger.log("Voice Q&A: smart search failed (using re-ranked BM25): \(error)", source: "VoiceQA")
                    }
                }

                // If no document results and no injected context, nothing to work with
                if results.isEmpty && injectedContext.isEmpty {
                    state = .error("No matching documents found")
                    return
                }

                // Deduplicate by file path
                var seen = Set<String>()
                results = results.filter { seen.insert($0.file).inserted }

                // Accumulate referenced documents (deduplicated across conversation)
                let existingFiles = Set(referencedDocuments.map(\.file))
                for doc in results where !existingFiles.contains(doc.file) {
                    referencedDocuments.append(doc)
                }

                let blocks = results.flatMap { $0.knowledgeBlocks ?? [] }
                state = .done(answer: "", sources: results, knowledgeBlocks: blocks)

                state = .answering
                var prompt = ""
                if !injectedContext.isEmpty {
                    let truncated = String(injectedContext.suffix(8000))
                    prompt += "## External Context\n\(truncated)\n\n"
                }
                // Include attached file contents
                if !currentAttachments.isEmpty {
                    prompt += "## Attached Files\n"
                    for url in currentAttachments {
                        if let content = SidecarCLI.readSidecarFile(sourcePath: url.path)
                            ?? (try? String(contentsOf: url, encoding: .utf8)) {
                            let truncated = String(content.prefix(4000))
                            prompt += "### \(url.lastPathComponent)\n\(truncated)\n\n"
                        }
                    }
                }
                if !conversationHistory.isEmpty {
                    prompt += "## Previous Q&A\n"
                    for entry in conversationHistory.suffix(3) {
                        prompt += "Q: \(entry.question)\nA: \(entry.answer)\n\n"
                    }
                }
                prompt += "## Question\n\(question)"
                if !results.isEmpty {
                    let docContext = ContextFormatter.format(results: results)
                    prompt += "\n\n## Documents\n\(docContext)"
                }

                let answer = try await SidecarCLI.askWithContext(
                    question: prompt,
                    context: "",
                    cliPath: settings.cliPath
                )

                conversationHistory.append((question: question, answer: answer, sources: results, attachments: currentAttachments))
                currentAttachments = []
                state = .done(answer: "", sources: results, knowledgeBlocks: blocks)

                // Process queued questions
                if !questionQueue.isEmpty {
                    let next = questionQueue.removeFirst()
                    Logger.log("Voice Q&A: processing queued question (\(questionQueue.count) remaining)", source: "VoiceQA")
                    partialTranscription = next
                    processQuestion(next)
                }
            } catch {
                state = .error("Failed: \(error.localizedDescription)")
            }
        }
    }

    func dismiss() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioSamples = []
        state = .idle
        partialTranscription = ""
        bufferEnergy = []
        conversationHistory = []
        referencedDocuments = []
        attachedFiles = []
        questionQueue = []
        injectedContext = ""
        pendingInput = ""
    }
}

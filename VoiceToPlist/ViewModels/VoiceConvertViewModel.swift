//
//  VoiceConvertViewModel.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/2.
//

import Foundation
import SwiftUI
import AVFoundation

/// ViewModel for voice conversion tab
@MainActor
class VoiceConvertViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var models: [RVCService.VoiceModel] = []
    @Published var isLoadingModels = false
    @Published var isServerAvailable = false

    @Published var selectedModel: RVCService.VoiceModel? {
        didSet {
            // Auto reconvert when model changes and we have recorded audio
            if oldValue?.id != selectedModel?.id,
               recordedAudioData != nil,
               convertedAudioData != nil,
               !isConverting {
                Task {
                    await reconvert()
                }
            }
        }
    }

    // Recording
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordedAudioURL: URL?
    @Published var recordedAudioData: Data?

    // Conversion
    @Published var isConverting = false
    @Published var convertedAudioData: Data?
    @Published var convertedAudioURL: URL?

    // Playback
    @Published var isPlayingOriginal = false
    @Published var isPlayingConverted = false
    @Published var isPlayingMixed = false

    // Noise recording
    @Published var isRecordingNoise = false
    @Published var noiseRecordingDuration: TimeInterval = 0
    @Published var noiseAudioURL: URL?
    @Published var noiseAudioData: Data?
    @Published var noiseVolume: Float = 1.0  // 0 ~ 2, default 100%
    @Published var mixedAudioData: Data?
    @Published var mixedAudioURL: URL?
    @Published var isPlayingNoise = false

    private var noiseRecorder: AVAudioRecorder?
    private var noiseRecordingTimer: Timer?

    // Status
    @Published var statusMessage = "正在连接服务器..."
    @Published var errorMessage: String?
    @Published var showError = false

    // Conversion options
    @Published var pitch: Double = 0  // -12 ~ 12
    @Published var f0Method: String = "rmvpe"  // rmvpe/crepe/harvest/pm
    @Published var indexRate: Double = 0.5  // 0 ~ 1
    @Published var filterRadius: Double = 3  // 0 ~ 7
    @Published var rmsMixRate: Double = 0.25  // 0 ~ 1
    @Published var protect: Double = 0.33  // 0 ~ 0.5

    // Blend mode (dual model fusion)
    @Published var isBlendMode: Bool = false {
        didSet {
            // Trigger reconvert when mode changes
            if oldValue != isBlendMode,
               recordedAudioData != nil,
               convertedAudioData != nil,
               !isConverting {
                Task {
                    await reconvert()
                }
            }
        }
    }
    @Published var selectedModel2: RVCService.VoiceModel? {
        didSet {
            // Auto reconvert when second model changes in blend mode
            if isBlendMode,
               oldValue?.id != selectedModel2?.id,
               recordedAudioData != nil,
               convertedAudioData != nil,
               !isConverting {
                Task {
                    await reconvert()
                }
            }
        }
    }
    @Published var blendRatio: Double = 0.5  // 0 = 100% model2, 1 = 100% model1

    static let f0Methods = ["rmvpe", "crepe", "harvest", "pm"]

    // 可融合的模型列表（与当前选中模型兼容的模型）
    var compatibleModelsForBlend: [RVCService.VoiceModel] {
        guard let model1 = selectedModel else { return [] }
        return models.filter { model1.canBlendWith($0) }
    }

    // MARK: - Private Properties

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?

    // MARK: - Initialization

    init() {
        Task {
            await checkServerAndLoadModels()
        }
    }

    // MARK: - Server & Models

    func checkServerAndLoadModels() async {
        isLoadingModels = true
        statusMessage = "正在检查服务器..."

        isServerAvailable = await RVCService.shared.isServerAvailable()

        if isServerAvailable {
            do {
                models = try await RVCService.shared.fetchModels()
                if selectedModel == nil, let first = models.first {
                    selectedModel = first
                }
                statusMessage = "已加载 \(models.count) 个模型，长按下方按钮开始录音"
            } catch {
                statusMessage = "加载模型失败"
                showError(message: error.localizedDescription)
            }
        } else {
            statusMessage = "服务器不可用，请检查网络"
        }

        isLoadingModels = false
    }

    func refreshModels() async {
        await checkServerAndLoadModels()
    }

    // MARK: - Recording

    func startRecording() {
        // Request permission
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                if granted {
                    self?.beginRecording()
                } else {
                    self?.showError(message: "请在设置中允许麦克风权限")
                }
            }
        }
    }

    private func beginRecording() {
        // Clear previous recordings and noise
        convertedAudioData = nil
        convertedAudioURL = nil
        clearNoise()
        stopPlayback()

        // Setup audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            showError(message: "无法启动录音: \(error.localizedDescription)")
            return
        }

        // Create recording URL
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).m4a")
        recordedAudioURL = tempURL

        // Recording settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordingDuration = 0
            statusMessage = "正在录音..."

            // Start timer
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingDuration += 0.1
                }
            }
        } catch {
            showError(message: "录音失败: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        // Load recorded data
        if let url = recordedAudioURL {
            do {
                recordedAudioData = try Data(contentsOf: url)
                statusMessage = String(format: "录音完成 (%.1f秒)，正在转换...", recordingDuration)

                // Auto convert after recording
                Task {
                    await convert()
                }
            } catch {
                showError(message: "无法读取录音: \(error.localizedDescription)")
            }
        }
    }

    func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        // Delete recorded file
        if let url = recordedAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedAudioURL = nil
        recordedAudioData = nil
        recordingDuration = 0
        statusMessage = "录音已取消"
    }

    // MARK: - Conversion

    func convert() async {
        guard let audioData = recordedAudioData,
              let audioURL = recordedAudioURL,
              let model = selectedModel else {
            showError(message: "请先录音并选择模型")
            return
        }

        // Check blend mode requirements
        if isBlendMode {
            guard let model2 = selectedModel2 else {
                showError(message: "融合模式需要选择第二个模型")
                return
            }
            if model.id == model2.id {
                showError(message: "请选择两个不同的模型进行融合")
                return
            }
        }

        guard isServerAvailable else {
            showError(message: "服务器不可用，请稍后重试")
            return
        }

        isConverting = true
        statusMessage = isBlendMode ? "正在融合转换中，请稍候..." : "正在转换中，请稍候..."
        stopPlayback()

        do {
            let options = RVCService.ConvertOptions(
                pitch: Int(pitch),
                f0Method: f0Method,
                indexRate: Float(indexRate),
                filterRadius: Int(filterRadius),
                rmsMixRate: Float(rmsMixRate),
                protect: Float(protect)
            )

            let resultData: Data

            if isBlendMode, let model2 = selectedModel2 {
                // Blend mode - use two models
                resultData = try await RVCService.shared.convertBlend(
                    audioData: audioData,
                    filename: audioURL.lastPathComponent,
                    model1Name: model.name,
                    model2Name: model2.name,
                    blendRatio: Float(blendRatio),
                    options: options
                )
            } else {
                // Single model mode
                resultData = try await RVCService.shared.convert(
                    audioData: audioData,
                    filename: audioURL.lastPathComponent,
                    modelName: model.name,
                    options: options
                )
            }

            // Save to temp file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("converted_\(UUID().uuidString).wav")
            try resultData.write(to: tempURL)

            convertedAudioData = resultData
            convertedAudioURL = tempURL
            statusMessage = isBlendMode ? "融合转换完成！点击播放试听" : "转换完成！点击播放试听"
        } catch {
            showError(message: error.localizedDescription)
            statusMessage = "转换失败，请重试"
        }

        isConverting = false
    }

    /// Reconvert with current parameters, clearing noise data
    func reconvert() async {
        // Clear noise and mixed audio before reconverting
        clearNoise()

        // Clear previous converted audio
        if let url = convertedAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        convertedAudioData = nil
        convertedAudioURL = nil

        // Reconvert
        await convert()
    }

    // MARK: - Playback

    func playOriginal() {
        guard let url = recordedAudioURL else { return }
        stopPlayback()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = VoiceConvertPlayerDelegate.shared
            VoiceConvertPlayerDelegate.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.isPlayingOriginal = false
                }
            }
            audioPlayer?.play()
            isPlayingOriginal = true
        } catch {
            showError(message: "播放失败: \(error.localizedDescription)")
        }
    }

    func playConverted() {
        guard let url = convertedAudioURL else { return }
        stopPlayback()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = VoiceConvertPlayerDelegate.shared
            VoiceConvertPlayerDelegate.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.isPlayingConverted = false
                }
            }
            audioPlayer?.play()
            isPlayingConverted = true
        } catch {
            showError(message: "播放失败: \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingOriginal = false
        isPlayingConverted = false
        isPlayingMixed = false
        isPlayingNoise = false
    }

    // MARK: - Noise Recording

    /// Get the duration of converted audio in seconds
    var convertedAudioDuration: TimeInterval {
        guard let url = convertedAudioURL else { return 0 }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            return player.duration
        } catch {
            return 0
        }
    }

    /// Required noise recording duration
    var requiredNoiseDuration: TimeInterval {
        return convertedAudioDuration
    }

    /// Formatted required duration
    var formattedRequiredDuration: String {
        let total = Int(ceil(requiredNoiseDuration))
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return "\(seconds)秒"
    }

    /// Formatted noise recording duration
    var formattedNoiseRecordingDuration: String {
        let minutes = Int(noiseRecordingDuration) / 60
        let seconds = Int(noiseRecordingDuration) % 60
        let tenths = Int((noiseRecordingDuration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    /// Remaining time for noise recording
    var remainingNoiseTime: TimeInterval {
        return max(0, requiredNoiseDuration - noiseRecordingDuration)
    }

    /// Whether noise recording has reached required duration
    var isNoiseRecordingComplete: Bool {
        return noiseRecordingDuration >= requiredNoiseDuration
    }

    func startNoiseRecording() {
        guard convertedAudioData != nil else {
            showError(message: "请先完成语音转换")
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                if granted {
                    self?.beginNoiseRecording()
                } else {
                    self?.showError(message: "请在设置中允许麦克风权限")
                }
            }
        }
    }

    private func beginNoiseRecording() {
        // Clear previous noise
        noiseAudioData = nil
        noiseAudioURL = nil
        mixedAudioData = nil
        mixedAudioURL = nil
        stopPlayback()

        // Setup audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            showError(message: "无法启动录音: \(error.localizedDescription)")
            return
        }

        // Create recording URL
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("noise_\(UUID().uuidString).wav")
        noiseAudioURL = tempURL

        // Recording settings - use WAV for easier mixing
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            noiseRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
            noiseRecorder?.record()
            isRecordingNoise = true
            noiseRecordingDuration = 0
            statusMessage = "正在录制底噪..."

            // Start timer
            noiseRecordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.noiseRecordingDuration += 0.1

                    // Auto stop when reaching required duration
                    if self.noiseRecordingDuration >= self.requiredNoiseDuration {
                        self.stopNoiseRecording()
                    }
                }
            }
        } catch {
            showError(message: "录音失败: \(error.localizedDescription)")
        }
    }

    func stopNoiseRecording() {
        guard isRecordingNoise else { return }

        noiseRecordingTimer?.invalidate()
        noiseRecordingTimer = nil

        noiseRecorder?.stop()
        noiseRecorder = nil
        isRecordingNoise = false

        // Check if duration is sufficient
        if noiseRecordingDuration < requiredNoiseDuration {
            // Recording too short, invalid
            if let url = noiseAudioURL {
                try? FileManager.default.removeItem(at: url)
            }
            noiseAudioURL = nil
            noiseAudioData = nil
            noiseRecordingDuration = 0
            showError(message: "底噪录制时长不足，请录满 \(formattedRequiredDuration)")
            statusMessage = "底噪录制失败"
            return
        }

        // Load recorded data
        if let url = noiseAudioURL {
            do {
                noiseAudioData = try Data(contentsOf: url)
                statusMessage = "底噪录制完成，正在混合..."

                // Auto mix after recording
                Task {
                    await mixAudio()
                }
            } catch {
                showError(message: "无法读取底噪: \(error.localizedDescription)")
            }
        }
    }

    func cancelNoiseRecording() {
        noiseRecordingTimer?.invalidate()
        noiseRecordingTimer = nil

        noiseRecorder?.stop()
        noiseRecorder = nil
        isRecordingNoise = false

        // Delete recorded file
        if let url = noiseAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        noiseAudioURL = nil
        noiseAudioData = nil
        noiseRecordingDuration = 0
        statusMessage = "底噪录制已取消"
    }

    // MARK: - Audio Mixing

    func mixAudio() async {
        guard let convertedURL = convertedAudioURL,
              let noiseURL = noiseAudioURL else {
            showError(message: "缺少音频数据")
            return
        }

        statusMessage = "正在混合音频..."

        do {
            let mixedData = try await performAudioMix(
                voiceURL: convertedURL,
                noiseURL: noiseURL,
                noiseVolume: noiseVolume
            )

            // Save mixed audio
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mixed_\(UUID().uuidString).wav")
            try mixedData.write(to: tempURL)

            mixedAudioData = mixedData
            mixedAudioURL = tempURL
            statusMessage = "混合完成！可以试听效果"
        } catch {
            showError(message: "混合失败: \(error.localizedDescription)")
        }
    }

    private func performAudioMix(voiceURL: URL, noiseURL: URL, noiseVolume: Float) async throws -> Data {
        // Use AVAudioFile for reliable reading, then mix manually

        let voiceFile = try AVAudioFile(forReading: voiceURL)
        let noiseFile = try AVAudioFile(forReading: noiseURL)

        let voiceFormat = voiceFile.processingFormat
        let noiseFormat = noiseFile.processingFormat

        let voiceFrameCount = AVAudioFrameCount(voiceFile.length)
        let noiseFrameCount = AVAudioFrameCount(noiseFile.length)

        // Create buffers
        guard let voiceBuffer = AVAudioPCMBuffer(pcmFormat: voiceFormat, frameCapacity: voiceFrameCount),
              let noiseBuffer = AVAudioPCMBuffer(pcmFormat: noiseFormat, frameCapacity: noiseFrameCount) else {
            throw NSError(domain: "AudioMix", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建缓冲区"])
        }

        try voiceFile.read(into: voiceBuffer)
        try noiseFile.read(into: noiseBuffer)

        // Get sample data - handle both float and int16 formats
        let voiceSampleCount = Int(voiceBuffer.frameLength)
        let noiseSampleCount = Int(noiseBuffer.frameLength)

        var voiceSamples = [Float](repeating: 0, count: voiceSampleCount)
        var noiseSamples = [Float](repeating: 0, count: noiseSampleCount)

        // Read voice samples
        if let floatData = voiceBuffer.floatChannelData {
            for i in 0..<voiceSampleCount {
                voiceSamples[i] = floatData[0][i]
            }
        } else if let int16Data = voiceBuffer.int16ChannelData {
            for i in 0..<voiceSampleCount {
                voiceSamples[i] = Float(int16Data[0][i]) / 32768.0
            }
        }

        // Read noise samples
        if let floatData = noiseBuffer.floatChannelData {
            for i in 0..<noiseSampleCount {
                noiseSamples[i] = floatData[0][i]
            }
        } else if let int16Data = noiseBuffer.int16ChannelData {
            for i in 0..<noiseSampleCount {
                noiseSamples[i] = Float(int16Data[0][i]) / 32768.0
            }
        }

        // Mix samples
        var outputSamples = [Int16](repeating: 0, count: voiceSampleCount)
        for i in 0..<voiceSampleCount {
            let noiseIndex = i % max(1, noiseSampleCount)
            var mixed = voiceSamples[i] + noiseSamples[noiseIndex] * noiseVolume

            // Clamp to [-1, 1] then convert to Int16
            mixed = max(-1.0, min(1.0, mixed))
            outputSamples[i] = Int16(mixed * 32767.0)
        }

        // Create WAV file manually
        let sampleRate = UInt32(voiceFormat.sampleRate)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(voiceSampleCount * 2)
        let fileSize = 36 + dataSize

        var wavData = Data()

        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })  // chunk size
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })   // audio format (PCM)
        wavData.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        // PCM data
        outputSamples.withUnsafeBytes { ptr in
            wavData.append(contentsOf: ptr)
        }

        return wavData
    }

    /// Update noise volume and remix
    func updateNoiseVolume(_ volume: Float) {
        noiseVolume = volume
        if noiseAudioData != nil && convertedAudioData != nil {
            Task {
                await mixAudio()
            }
        }
    }

    func playMixed() {
        guard let url = mixedAudioURL else { return }
        stopPlayback()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = VoiceConvertPlayerDelegate.shared
            VoiceConvertPlayerDelegate.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.isPlayingMixed = false
                }
            }
            audioPlayer?.play()
            isPlayingMixed = true
        } catch {
            showError(message: "播放失败: \(error.localizedDescription)")
        }
    }

    func playNoise() {
        guard let url = noiseAudioURL else { return }
        stopPlayback()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = VoiceConvertPlayerDelegate.shared
            VoiceConvertPlayerDelegate.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.isPlayingNoise = false
                }
            }
            audioPlayer?.play()
            isPlayingNoise = true
        } catch {
            showError(message: "播放失败: \(error.localizedDescription)")
        }
    }

    /// Clear noise and mixed audio
    func clearNoise() {
        if let url = noiseAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = mixedAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        noiseAudioURL = nil
        noiseAudioData = nil
        mixedAudioURL = nil
        mixedAudioData = nil
        noiseRecordingDuration = 0
        statusMessage = "底噪已清除"
    }

    // MARK: - Import Audio/Video

    private static let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "3gp"]

    /// Import audio from a file URL (supports both audio and video files)
    func importAudio(from url: URL) async {
        // Clear previous recordings and noise
        convertedAudioData = nil
        convertedAudioURL = nil
        clearNoise()
        stopPlayback()

        let ext = url.pathExtension.lowercased()
        let isVideo = Self.videoExtensions.contains(ext)

        statusMessage = isVideo ? "正在提取视频音频..." : "正在导入音频..."

        do {
            // Start accessing security-scoped resource if needed
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let audioURL: URL

            if isVideo {
                // Extract audio from video
                audioURL = try await extractAudioFromVideo(url)
            } else {
                // Copy audio file to temp location
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("imported_\(UUID().uuidString).\(ext)")
                try FileManager.default.copyItem(at: url, to: tempURL)
                audioURL = tempURL
            }

            // Get audio duration
            let asset = AVAsset(url: audioURL)
            let duration = try await asset.load(.duration)
            recordingDuration = CMTimeGetSeconds(duration)

            recordedAudioURL = audioURL
            recordedAudioData = try Data(contentsOf: audioURL)

            statusMessage = String(format: "已导入音频 (%.1f秒)，正在转换...", recordingDuration)

            // Auto convert after import
            await convert()
        } catch {
            showError(message: "导入失败: \(error.localizedDescription)")
            statusMessage = "导入失败"
        }
    }

    /// Extract audio track from video file
    private func extractAudioFromVideo(_ videoURL: URL) async throws -> URL {
        let asset = AVAsset(url: videoURL)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("extracted_\(UUID().uuidString).m4a")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw NSError(domain: "Export", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "无法创建导出会话"])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }

        guard exportSession.status == .completed else {
            throw NSError(domain: "Export", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "音频提取失败"])
        }

        return outputURL
    }

    // MARK: - Helpers

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }

    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        let tenths = Int((recordingDuration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Audio Player Delegate

class VoiceConvertPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    static let shared = VoiceConvertPlayerDelegate()
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}

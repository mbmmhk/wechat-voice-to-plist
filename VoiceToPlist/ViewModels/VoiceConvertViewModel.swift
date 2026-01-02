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
    @Published var selectedModel: RVCService.VoiceModel?
    @Published var isLoadingModels = false
    @Published var isServerAvailable = false

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

    static let f0Methods = ["rmvpe", "crepe", "harvest", "pm"]

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
        // Clear previous recordings
        convertedAudioData = nil
        convertedAudioURL = nil
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

        guard isServerAvailable else {
            showError(message: "服务器不可用，请稍后重试")
            return
        }

        isConverting = true
        statusMessage = "正在转换中，请稍候..."
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

            let resultData = try await RVCService.shared.convert(
                audioData: audioData,
                filename: audioURL.lastPathComponent,
                modelName: model.name,
                options: options
            )

            // Save to temp file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("converted_\(UUID().uuidString).wav")
            try resultData.write(to: tempURL)

            convertedAudioData = resultData
            convertedAudioURL = tempURL
            statusMessage = "转换完成！点击播放试听"
        } catch {
            showError(message: error.localizedDescription)
            statusMessage = "转换失败，请重试"
        }

        isConverting = false
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

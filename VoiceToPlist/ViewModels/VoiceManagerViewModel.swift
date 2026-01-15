//
//  VoiceManagerViewModel.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/1.
//

import Foundation
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Main view model for the voice manager
@MainActor
class VoiceManagerViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var entries: [AudioEntry] = []
    @Published var selectedEntries: Set<UUID> = []
    @Published var currentPlistURL: URL?
    @Published var isModified: Bool = false
    @Published var isLoading: Bool = false
    @Published var isConverting: Bool = false
    @Published var conversionProgress: Double = 0
    @Published var statusMessage: String = "就绪"
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var currentlyPlaying: UUID?

    // MARK: - Audio Player

    private var audioPlayer: AVAudioPlayer?
    private var tempWavURL: URL?

    // MARK: - Supported Formats

    static let supportedAudioExtensions = ["mp3", "wav", "m4a", "aac", "ogg", "flac", "caf"]
    static let supportedVideoExtensions = ["mp4", "mov", "m4v"]
    static let allSupportedExtensions = supportedAudioExtensions + supportedVideoExtensions

    // MARK: - Computed Properties

    var windowTitle: String {
        if let url = currentPlistURL {
            let name = url.lastPathComponent
            return isModified ? "语音包管理器 - \(name) *" : "语音包管理器 - \(name)"
        }
        return isModified ? "语音包管理器 - 新建 *" : "语音包管理器"
    }

    var fileInfo: String {
        if let url = currentPlistURL {
            return "📁 \(url.path) (\(entries.count) 个音频)"
        }
        return entries.isEmpty ? "未加载文件 - 拖入 plist 文件或点击「打开」" : "📄 新建语音包（未保存）"
    }

    // MARK: - Plist Operations

    /// Generate duration prefix for audio name (e.g., "5秒-" or "1分23秒-")
    private func generateDurationPrefix(for silkData: Data) -> String {
        guard SilkCodec.isValidSilk(silkData) else { return "" }

        do {
            let pcmData = try SilkCodec.decode(silkData)
            let samples = pcmData.count / 2
            let duration = Double(samples) / 24000.0
            let totalSeconds = Int(round(duration))

            if totalSeconds < 60 {
                return "\(totalSeconds)秒-"
            } else {
                let minutes = totalSeconds / 60
                let seconds = totalSeconds % 60
                if seconds == 0 {
                    return "\(minutes)分-"
                }
                return "\(minutes)分\(seconds)秒-"
            }
        } catch {
            return ""
        }
    }

    /// Format name with duration prefix
    func formatNameWithDuration(originalName: String, silkData: Data) -> String {
        let prefix = generateDurationPrefix(for: silkData)
        // Remove any existing duration prefix pattern
        let cleanName = removeExistingDurationPrefix(from: originalName)
        return prefix + cleanName
    }

    /// Remove existing duration prefix from name
    private func removeExistingDurationPrefix(from name: String) -> String {
        // Match patterns like "5秒-", "1分-", "1分23秒-"
        let pattern = "^\\d+秒-|^\\d+分-|^\\d+分\\d+秒-"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(name.startIndex..., in: name)
            return regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "")
        }
        return name
    }

    /// Load a plist file
    func loadPlist(from url: URL) {
        isLoading = true
        statusMessage = "正在加载..."

        Task {
            do {
                // Request security scoped access
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                var loadedEntries = try PlistManager.loadPlist(from: url)

                // Add duration prefix to all entries
                for i in 0..<loadedEntries.count {
                    let formattedName = formatNameWithDuration(
                        originalName: loadedEntries[i].name,
                        silkData: loadedEntries[i].silkData
                    )
                    loadedEntries[i].name = formattedName
                }

                await MainActor.run {
                    self.entries = loadedEntries
                    self.currentPlistURL = url
                    self.isModified = false
                    self.selectedEntries.removeAll()
                    self.statusMessage = "已加载 \(loadedEntries.count) 个音频"
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.showError(message: "加载失败: \(error.localizedDescription)")
                    self.isLoading = false
                }
            }
        }
    }

    /// Save to current plist file
    func savePlist() {
        guard let url = currentPlistURL else {
            // No current file, need to save as new
            return
        }

        do {
            // Request security scoped access for writing
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try PlistManager.savePlist(entries: entries, to: url)
            isModified = false
            statusMessage = "保存成功"
        } catch {
            showError(message: "保存失败: \(error.localizedDescription)")
        }
    }

    /// Save to a new plist file
    func savePlistAs(to url: URL) {
        do {
            // Request security scoped access for writing
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try PlistManager.savePlist(entries: entries, to: url)
            currentPlistURL = url
            isModified = false
            statusMessage = "保存成功"
        } catch {
            showError(message: "保存失败: \(error.localizedDescription)")
        }
    }

    /// Create a new empty plist
    func createNew() {
        stopPlayback()
        entries = []
        currentPlistURL = nil
        isModified = false
        selectedEntries.removeAll()
        statusMessage = "新建语音包"
    }

    // MARK: - Audio Playback

    /// Play audio for an entry
    func playAudio(for entry: AudioEntry) {
        stopPlayback()

        guard entry.isValidSilk else {
            showError(message: "无效的 SILK 音频数据")
            return
        }

        do {
            let wavData = try SilkCodec.silkToWav(entry.silkData)

            // Save to temp file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
            try wavData.write(to: tempURL)
            tempWavURL = tempURL

            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.delegate = AudioPlayerDelegateHandler.shared
            AudioPlayerDelegateHandler.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.currentlyPlaying = nil
                    self?.statusMessage = "播放完成"
                }
            }

            audioPlayer?.play()
            currentlyPlaying = entry.id
            statusMessage = "正在播放: \(entry.name)"
        } catch {
            showError(message: "播放失败: \(error.localizedDescription)")
        }
    }

    /// Stop current playback
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentlyPlaying = nil

        // Clean up temp file
        if let tempURL = tempWavURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempWavURL = nil
        }

        statusMessage = "已停止"
    }

    // MARK: - Entry Management

    /// Add audio files
    func addAudioFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }

        // Filter valid files
        let validURLs = urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return Self.allSupportedExtensions.contains(ext)
        }

        guard !validURLs.isEmpty else {
            showError(message: "不支持的格式。支持: \(Self.allSupportedExtensions.joined(separator: ", "))")
            return
        }

        isConverting = true
        conversionProgress = 0

        Task {
            var successCount = 0
            let total = validURLs.count

            for (index, url) in validURLs.enumerated() {
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                await MainActor.run {
                    statusMessage = "正在转换: \(url.lastPathComponent)"
                    conversionProgress = Double(index) / Double(total)
                }

                do {
                    let silkData = try await AudioConverter.audioToSilk(from: url)
                    let name = url.deletingPathExtension().lastPathComponent

                    // Check for duplicate names
                    var finalName = name
                    var counter = 1
                    while entries.contains(where: { $0.name == finalName }) {
                        finalName = "\(name)_\(counter)"
                        counter += 1
                    }

                    // Format name with duration prefix
                    let formattedName = formatNameWithDuration(originalName: finalName, silkData: silkData)
                    let entry = AudioEntry(name: formattedName, silkData: silkData)

                    await MainActor.run {
                        entries.append(entry)
                        isModified = true
                    }

                    successCount += 1
                } catch {
                    print("转换失败 \(url.lastPathComponent): \(error)")
                }
            }

            await MainActor.run {
                isConverting = false
                conversionProgress = 1.0
                statusMessage = "添加完成: \(successCount)/\(total) 个文件"
            }
        }
    }

    /// Rename an entry (preserves duration prefix)
    func renameEntry(_ entry: AudioEntry, to newName: String) {
        guard !newName.isEmpty else { return }

        // Remove any existing duration prefix from user input and regenerate
        let cleanNewName = removeExistingDurationPrefix(from: newName)
        let formattedName = formatNameWithDuration(originalName: cleanNewName, silkData: entry.silkData)

        // Check for duplicate names
        if entries.contains(where: { $0.id != entry.id && $0.name == formattedName }) {
            showError(message: "名称已存在")
            return
        }

        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].name = formattedName
            isModified = true
            statusMessage = "已重命名"
        }
    }

    /// Delete selected entries
    func deleteSelected() {
        let count = selectedEntries.count
        entries.removeAll { selectedEntries.contains($0.id) }
        selectedEntries.removeAll()
        isModified = true
        statusMessage = "已删除 \(count) 个音频"
    }

    /// Delete a single entry
    func deleteEntry(_ entry: AudioEntry) {
        if currentlyPlaying == entry.id {
            stopPlayback()
        }
        entries.removeAll { $0.id == entry.id }
        selectedEntries.remove(entry.id)
        isModified = true
        statusMessage = "已删除: \(entry.name)"
    }

    // MARK: - Export

    /// Export a single entry to WAV
    func exportEntry(_ entry: AudioEntry, to url: URL) {
        Task {
            do {
                try await AudioConverter.exportSilk(entry.silkData, to: url.pathExtension, at: url)
                await MainActor.run {
                    statusMessage = "已导出: \(url.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    showError(message: "导出失败: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Export all entries to a directory
    func exportAll(to directoryURL: URL, format: String = "wav") {
        guard !entries.isEmpty else {
            showError(message: "没有音频可导出")
            return
        }

        isConverting = true
        conversionProgress = 0

        Task {
            var successCount = 0
            let total = entries.count

            for (index, entry) in entries.enumerated() {
                await MainActor.run {
                    statusMessage = "正在导出: \(entry.name)"
                    conversionProgress = Double(index) / Double(total)
                }

                // Sanitize filename
                let safeName = entry.name
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: ":", with: "_")
                    .prefix(50)

                let outputURL = directoryURL.appendingPathComponent("\(safeName).\(format)")

                do {
                    try await AudioConverter.exportSilk(entry.silkData, to: format, at: outputURL)
                    successCount += 1
                } catch {
                    print("导出失败 \(entry.name): \(error)")
                }
            }

            await MainActor.run {
                isConverting = false
                conversionProgress = 1.0
                statusMessage = "已导出 \(successCount)/\(total) 个音频"
            }
        }
    }

    // MARK: - Helpers

    private func showError(message: String) {
        errorMessage = message
        showError = true
        statusMessage = message
    }

    /// Handle dropped files (plist or audio)
    func handleDroppedFiles(_ urls: [URL]) {
        // Check if any is a plist
        if let plistURL = urls.first(where: { $0.pathExtension.lowercased() == "plist" }) {
            loadPlist(from: plistURL)
            return
        }

        // Otherwise treat as audio files
        addAudioFiles(urls: urls)
    }
}

// MARK: - Audio Player Delegate Handler

class AudioPlayerDelegateHandler: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayerDelegateHandler()
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}

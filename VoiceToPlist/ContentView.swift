//
//  ContentView.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/1.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = VoiceManagerViewModel()
    @State private var showOpenPicker = false
    @State private var showSavePicker = false
    @State private var showAddAudioPicker = false
    @State private var showPhotoPicker = false
    @State private var showExportPicker = false
    @State private var entryToRename: AudioEntry?
    @State private var newName: String = ""
    @State private var showRenameAlert = false
    @State private var entryToExport: AudioEntry?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // File info header
                Text(viewModel.fileInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Audio list
                if viewModel.entries.isEmpty {
                    emptyStateView
                } else {
                    audioListView
                }

                // Hint label
                Text("💡 点击播放 | 长按更多操作 | 拖入文件添加")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)

                // Control buttons
                controlButtonsView

                // Progress bar
                if viewModel.isConverting {
                    ProgressView(value: viewModel.conversionProgress)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // Status bar
                HStack {
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("语音包管理器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: { showOpenPicker = true }) {
                            Label("打开 plist", systemImage: "folder")
                        }
                        Button(action: viewModel.createNew) {
                            Label("新建", systemImage: "doc.badge.plus")
                        }
                        Divider()
                        Button(action: {
                            if viewModel.currentPlistURL != nil {
                                viewModel.savePlist()
                            } else {
                                showSavePicker = true
                            }
                        }) {
                            Label("保存", systemImage: "square.and.arrow.down")
                        }
                        .disabled(viewModel.entries.isEmpty)

                        Button(action: { showSavePicker = true }) {
                            Label("另存为", systemImage: "square.and.arrow.down.on.square")
                        }
                        Divider()
                        Button(action: { showExportPicker = true }) {
                            Label("导出所有音频", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.entries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showAddAudioPicker = true }) {
                            Label("从文件添加", systemImage: "folder")
                        }
                        Button(action: { showPhotoPicker = true }) {
                            Label("从相册添加", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
        .sheet(isPresented: $showOpenPicker) {
            DocumentPickerView(
                contentTypes: [.data],
                onPick: { url in
                    if url.pathExtension.lowercased() == "plist" {
                        viewModel.loadPlist(from: url)
                    } else {
                        viewModel.errorMessage = "请选择 .plist 文件"
                        viewModel.showError = true
                    }
                }
            )
        }
        .fileImporter(
            isPresented: $showAddAudioPicker,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                viewModel.addAudioFiles(urls: urls)
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView { urls in
                viewModel.addAudioFiles(urls: urls)
            }
        }
        .fileExporter(
            isPresented: $showSavePicker,
            document: PlistDocument(entries: viewModel.entries),
            contentType: .propertyList,
            defaultFilename: "voice_pack"
        ) { result in
            if case .success(let url) = result {
                viewModel.savePlistAs(to: url)
            }
        }
        .sheet(isPresented: $showExportPicker) {
            ExportDirectoryPicker { url in
                if let url = url {
                    viewModel.exportAll(to: url)
                }
            }
        }
        .alert("重命名", isPresented: $showRenameAlert) {
            TextField("名称", text: $newName)
            Button("取消", role: .cancel) { }
            Button("确定") {
                if let entry = entryToRename {
                    viewModel.renameEntry(entry, to: newName)
                }
            }
        } message: {
            Text("请输入新名称")
        }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("拖入 plist 文件或音频文件")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("支持 MP3, WAV, M4A, AAC, MP4 等格式")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var audioListView: some View {
        List {
            ForEach(viewModel.entries) { entry in
                AudioRowView(
                    entry: entry,
                    isPlaying: viewModel.currentlyPlaying == entry.id,
                    onPlay: {
                        if viewModel.currentlyPlaying == entry.id {
                            viewModel.stopPlayback()
                        } else {
                            viewModel.playAudio(for: entry)
                        }
                    }
                )
                .contextMenu {
                    Button(action: {
                        if viewModel.currentlyPlaying == entry.id {
                            viewModel.stopPlayback()
                        } else {
                            viewModel.playAudio(for: entry)
                        }
                    }) {
                        Label(
                            viewModel.currentlyPlaying == entry.id ? "停止" : "播放",
                            systemImage: viewModel.currentlyPlaying == entry.id ? "stop.fill" : "play.fill"
                        )
                    }

                    Button(action: {
                        entryToRename = entry
                        newName = entry.name
                        showRenameAlert = true
                    }) {
                        Label("重命名", systemImage: "pencil")
                    }

                    Button(action: {
                        entryToExport = entry
                        // Export single entry - simplified for iOS
                        exportSingleEntry(entry)
                    }) {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive, action: {
                        viewModel.deleteEntry(entry)
                    }) {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.deleteEntry(entry)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var controlButtonsView: some View {
        HStack(spacing: 12) {
            Button(action: {
                if viewModel.currentlyPlaying != nil {
                    viewModel.stopPlayback()
                } else if let first = viewModel.entries.first {
                    viewModel.playAudio(for: first)
                }
            }) {
                HStack {
                    Image(systemName: viewModel.currentlyPlaying != nil ? "stop.fill" : "play.fill")
                    Text(viewModel.currentlyPlaying != nil ? "停止" : "播放")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.entries.isEmpty)

            Menu {
                Button(action: { showAddAudioPicker = true }) {
                    Label("从文件添加", systemImage: "folder")
                }
                Button(action: { showPhotoPicker = true }) {
                    Label("从相册添加", systemImage: "photo.on.rectangle")
                }
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("添加")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: {
                if viewModel.currentPlistURL != nil {
                    viewModel.savePlist()
                } else {
                    showSavePicker = true
                }
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("保存")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.entries.isEmpty)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                guard let urlData = data as? Data,
                      let urlString = String(data: urlData, encoding: .utf8),
                      let url = URL(string: urlString) else {
                    return
                }

                Task { @MainActor in
                    viewModel.handleDroppedFiles([url])
                }
            }
        }
    }

    private func exportSingleEntry(_ entry: AudioEntry) {
        Task {
            do {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(entry.name).wav")
                try await AudioConverter.exportSilk(entry.silkData, to: "wav", at: tempURL)

                await MainActor.run {
                    let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        rootVC.present(activityVC, animated: true)
                    }
                }
            } catch {
                await MainActor.run {
                    viewModel.showError = true
                    // viewModel.errorMessage is set internally
                }
            }
        }
    }
}

// MARK: - Audio Row View

struct AudioRowView: View {
    let entry: AudioEntry
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack {
                Image(systemName: isPlaying ? "speaker.wave.3.fill" : "waveform")
                    .foregroundColor(isPlaying ? .blue : .secondary)
                    .frame(width: 24)

                Text(entry.name)
                    .foregroundColor(.primary)

                Spacer()

                if isPlaying {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "play.circle")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plist Document for Export

struct PlistDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }
    static var writableContentTypes: [UTType] { [.propertyList] }

    var entries: [AudioEntry]

    init(entries: [AudioEntry]) {
        self.entries = entries
    }

    init(configuration: ReadConfiguration) throws {
        entries = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var dict: [String: String] = [:]
        for entry in entries {
            dict[entry.name] = entry.silkData.base64EncodedString()
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .xml,
            options: 0
        )

        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Export Directory Picker (Simplified for iOS)

struct ExportDirectoryPicker: View {
    let onSelect: (URL?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("导出到「文件」应用")
                    .font(.headline)

                Text("音频将被导出为 WAV 格式并保存到您选择的位置")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("选择导出位置") {
                    // On iOS, we export to Documents directory
                    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let exportURL = documentsURL.appendingPathComponent("VoiceExport_\(Date().timeIntervalSince1970)")
                    try? FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)
                    onSelect(exportURL)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                Button("取消") {
                    onSelect(nil)
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("导出音频")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Document Picker (UIKit wrapper for selecting any file)

struct DocumentPickerView: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Use .open mode without asCopy to get security-scoped access to the original file
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onPick(url)
            }
        }
    }
}

// MARK: - Photo Picker View (for selecting videos from photo library)

struct PhotoPickerView: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 0  // 0 means no limit
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: dismiss)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([URL]) -> Void
        let dismiss: DismissAction

        init(onPick: @escaping ([URL]) -> Void, dismiss: DismissAction) {
            self.onPick = onPick
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            dismiss()

            guard !results.isEmpty else { return }

            let group = DispatchGroup()
            var urls: [URL] = []

            for result in results {
                guard result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { continue }

                group.enter()
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    defer { group.leave() }

                    guard let url = url else { return }

                    // Copy to temp directory since the provided URL is temporary
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)

                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        urls.append(tempURL)
                    } catch {
                        print("Failed to copy video: \(error)")
                    }
                }
            }

            group.notify(queue: .main) {
                self.onPick(urls)
            }
        }
    }
}

#Preview {
    ContentView()
}

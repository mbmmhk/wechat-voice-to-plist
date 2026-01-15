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
    @ObservedObject var viewModel: VoiceManagerViewModel
    @State private var showOpenPicker = false
    @State private var showSavePicker = false
    @State private var showAddAudioPicker = false
    @State private var showPhotoPicker = false
    @State private var showExportPicker = false
    @State private var entryToRename: AudioEntry?
    @State private var newName: String = ""
    @State private var showRenameAlert = false
    @State private var entryToExport: AudioEntry?

    init(viewModel: VoiceManagerViewModel? = nil) {
        self._viewModel = ObservedObject(wrappedValue: viewModel ?? VoiceManagerViewModel())
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // File info header
                    fileInfoHeader

                    // Audio list or empty state
                    if viewModel.entries.isEmpty {
                        emptyStateView
                    } else {
                        audioListView
                    }

                    // Bottom bar
                    bottomBar
                }
            }
            .navigationTitle("语音包")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Section {
                            Button(action: { showOpenPicker = true }) {
                                Label("打开 plist", systemImage: "folder")
                            }
                            Button(action: viewModel.createNew) {
                                Label("新建", systemImage: "doc.badge.plus")
                            }
                        }

                        Section {
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
                        }

                        Section {
                            Button(action: { showExportPicker = true }) {
                                Label("导出所有音频", systemImage: "square.and.arrow.up")
                            }
                            .disabled(viewModel.entries.isEmpty)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .medium))
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

    // MARK: - File Info Header

    private var fileInfoHeader: some View {
        HStack(spacing: 12) {
            // File icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(viewModel.currentPlistURL != nil ?
                          LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                          LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)

                Image(systemName: viewModel.currentPlistURL != nil ? "doc.fill" : "doc")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(viewModel.currentPlistURL != nil ? .white : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let url = viewModel.currentPlistURL {
                    Text(url.lastPathComponent)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("\(viewModel.entries.count) 个音频")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if viewModel.isModified {
                            Text("• 未保存")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    Text(viewModel.entries.isEmpty ? "未打开文件" : "新建语音包")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    if !viewModel.entries.isEmpty {
                        Text("\(viewModel.entries.count) 个音频 • 未保存")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            if viewModel.isLoading || viewModel.isConverting {
                ProgressView()
                    .scaleEffect(0.9)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 120, height: 120)

                Image(systemName: "waveform.circle")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("没有音频文件")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("拖入 plist 文件或添加音频")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                Button(action: { showOpenPicker = true }) {
                    HStack {
                        Image(systemName: "folder")
                        Text("打开 plist 文件")
                    }
                    .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)

                Button(action: { showAddAudioPicker = true }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("添加音频文件")
                    }
                    .frame(maxWidth: 200)
                }
                .buttonStyle(.bordered)
            }

            Text("支持 MP3, WAV, M4A, AAC, MP4 等格式")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Audio List

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
                .listRowBackground(Color(.secondarySystemGroupedBackground))
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                .swipeActions(edge: .leading) {
                    Button {
                        entryToRename = entry
                        newName = entry.name
                        showRenameAlert = true
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Progress bar
            if viewModel.isConverting {
                VStack(spacing: 4) {
                    ProgressView(value: viewModel.conversionProgress)
                        .tint(.blue)

                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // Action buttons
            HStack(spacing: 12) {
                // Play/Stop button
                Button(action: {
                    if viewModel.currentlyPlaying != nil {
                        viewModel.stopPlayback()
                    } else if let first = viewModel.entries.first {
                        viewModel.playAudio(for: first)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.currentlyPlaying != nil ? "stop.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(viewModel.currentlyPlaying != nil ? "停止" : "播放")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .foregroundColor(viewModel.entries.isEmpty ? .secondary : .primary)
                    .cornerRadius(10)
                }
                .disabled(viewModel.entries.isEmpty)

                // Add button
                Menu {
                    Button(action: { showAddAudioPicker = true }) {
                        Label("从文件添加", systemImage: "folder")
                    }
                    Button(action: { showPhotoPicker = true }) {
                        Label("从相册添加", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("添加")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }

                // Save button
                Button(action: {
                    if viewModel.currentPlistURL != nil {
                        viewModel.savePlist()
                    } else {
                        showSavePicker = true
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                        Text("保存")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(viewModel.entries.isEmpty ? Color.blue.opacity(0.5) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(viewModel.entries.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(
            Color(.secondarySystemGroupedBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -4)
        )
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
            HStack(spacing: 12) {
                // Play indicator
                ZStack {
                    Circle()
                        .fill(isPlaying ? Color.blue : Color(.tertiarySystemGroupedBackground))
                        .frame(width: 40, height: 40)

                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isPlaying ? .white : .blue)
                }

                // Name and duration
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if isPlaying {
                            Text("正在播放...")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else {
                            // Duration badge
                            Text(entry.shortDuration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Duration on the right
                if !isPlaying {
                    Text(entry.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(6)
                }

                // Waveform icon
                Image(systemName: isPlaying ? "waveform" : "waveform")
                    .font(.system(size: 16))
                    .foregroundColor(isPlaying ? .blue : .secondary)
                    .opacity(isPlaying ? 1 : 0.5)
            }
            .padding(.vertical, 8)
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

// MARK: - Export Directory Picker

struct ExportDirectoryPicker: View {
    let onSelect: (URL?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 100, height: 100)

                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 8) {
                    Text("导出音频")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("音频将被导出为 WAV 格式\n并保存到「文件」应用")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button(action: {
                        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let exportURL = documentsURL.appendingPathComponent("VoiceExport_\(Date().timeIntervalSince1970)")
                        try? FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)
                        onSelect(exportURL)
                        dismiss()
                    }) {
                        Text("开始导出")
                            .fontWeight(.semibold)
                            .frame(maxWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("取消") {
                        onSelect(nil)
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("导出音频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        onSelect(nil)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Document Picker

struct DocumentPickerView: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
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

// MARK: - Photo Picker View

struct PhotoPickerView: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 0
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

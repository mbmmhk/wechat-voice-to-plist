//
//  VoiceConvertView.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/2.
//

import SwiftUI

struct VoiceConvertView: View {
    @StateObject private var viewModel = VoiceConvertViewModel()
    @ObservedObject var voiceManager: VoiceManagerViewModel
    @Binding var selectedTab: Int
    @State private var showModelPicker = false
    @State private var showAddToPackAlert = false
    @State private var newEntryName = ""

    init(voiceManager: VoiceManagerViewModel? = nil, selectedTab: Binding<Int>? = nil) {
        self._voiceManager = ObservedObject(wrappedValue: voiceManager ?? VoiceManagerViewModel())
        self._selectedTab = selectedTab ?? .constant(1)
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Server status card
                            serverStatusCard
                                .padding(.top, 8)

                            // Model selection card
                            modelSelectionCard

                            // Parameters card
                            parametersCard

                            // Playback section (if audio available)
                            if viewModel.recordedAudioData != nil || viewModel.convertedAudioData != nil {
                                playbackCard
                            }

                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 16)
                    }

                    // Recording button area
                    recordingSection
                }
            }
            .navigationTitle("语音转换")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.refreshModels()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .disabled(viewModel.isLoadingModels)
                }
            }
            .sheet(isPresented: $showModelPicker) {
                modelPickerSheet
            }
            .alert("错误", isPresented: $viewModel.showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
            .alert("添加到语音包", isPresented: $showAddToPackAlert) {
                TextField("名称", text: $newEntryName)
                Button("取消", role: .cancel) { }
                Button("添加") {
                    addToVoicePack()
                }
            } message: {
                Text("请输入语音名称")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Server Status Card

    private var serverStatusCard: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(viewModel.isServerAvailable ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .frame(width: 36, height: 36)

                Circle()
                    .fill(viewModel.isServerAvailable ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isServerAvailable ? "服务器已连接" : "服务器未连接")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.isLoadingModels || viewModel.isConverting {
                ProgressView()
                    .scaleEffect(0.9)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - Model Selection Card

    private var modelSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("声音模型", systemImage: "person.wave.2.fill")
                .font(.headline)
                .foregroundColor(.primary)

            Button(action: { showModelPicker = true }) {
                HStack(spacing: 12) {
                    // Model icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(
                                colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 44, height: 44)

                        Image(systemName: "waveform")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.selectedModel?.name ?? "选择一个模型")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(viewModel.selectedModel != nil ? .primary : .secondary)

                        if viewModel.isLoadingModels {
                            Text("加载中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(viewModel.models.count) 个模型可用")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .disabled(viewModel.models.isEmpty)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - Parameters Card

    private var parametersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("转换参数", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 20) {
                // Pitch
                parameterRow(
                    icon: "music.note",
                    iconColor: .orange,
                    title: "音高调整",
                    value: "\(Int(viewModel.pitch)) 半音",
                    hint: "正值提高音调（男转女），负值降低音调（女转男）"
                ) {
                    Slider(value: $viewModel.pitch, in: -12...12, step: 1)
                        .tint(.orange)
                }

                Divider()
                    .padding(.horizontal, -16)

                // F0 Method
                HStack {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.purple)
                        .frame(width: 20)

                    Text("F0提取方法")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Picker("", selection: $viewModel.f0Method) {
                        ForEach(VoiceConvertViewModel.f0Methods, id: \.self) { method in
                            Text(method.uppercased()).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.purple)
                }

                Text("rmvpe 效果最好，crepe 更精准但较慢")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()
                    .padding(.horizontal, -16)

                // Index Rate
                parameterRow(
                    icon: "person.fill.viewfinder",
                    iconColor: .blue,
                    title: "音色相似度",
                    value: String(format: "%.0f%%", viewModel.indexRate * 100),
                    hint: "越高越像目标音色，但可能不自然"
                ) {
                    Slider(value: $viewModel.indexRate, in: 0...1, step: 0.1)
                        .tint(.blue)
                }

                Divider()
                    .padding(.horizontal, -16)

                // Filter Radius
                parameterRow(
                    icon: "circle.hexagongrid",
                    iconColor: .cyan,
                    title: "中值滤波",
                    value: "\(Int(viewModel.filterRadius))",
                    hint: "值越大音质越平滑，但可能丢失细节"
                ) {
                    Slider(value: $viewModel.filterRadius, in: 0...7, step: 1)
                        .tint(.cyan)
                }

                Divider()
                    .padding(.horizontal, -16)

                // RMS Mix Rate
                parameterRow(
                    icon: "speaker.wave.2",
                    iconColor: .indigo,
                    title: "音量包络",
                    value: String(format: "%.0f%%", viewModel.rmsMixRate * 100),
                    hint: "混合输入音频的音量变化"
                ) {
                    Slider(value: $viewModel.rmsMixRate, in: 0...1, step: 0.05)
                        .tint(.indigo)
                }

                Divider()
                    .padding(.horizontal, -16)

                // Protect
                parameterRow(
                    icon: "shield.fill",
                    iconColor: .green,
                    title: "辅音保护",
                    value: String(format: "%.0f%%", viewModel.protect * 200),
                    hint: "保护清辅音和呼吸声，减少电音感"
                ) {
                    Slider(value: $viewModel.protect, in: 0...0.5, step: 0.05)
                        .tint(.green)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    private func parameterRow<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        value: String,
        hint: String,
        @ViewBuilder slider: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(iconColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(iconColor.opacity(0.1))
                    .cornerRadius(6)
            }

            slider()

            Text(hint)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Playback Card

    private var playbackCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("音频试听", systemImage: "headphones")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                // Original audio
                if viewModel.recordedAudioData != nil {
                    PlaybackButton(
                        title: "原始录音",
                        icon: "waveform",
                        isPlaying: viewModel.isPlayingOriginal,
                        color: .blue
                    ) {
                        if viewModel.isPlayingOriginal {
                            viewModel.stopPlayback()
                        } else {
                            viewModel.playOriginal()
                        }
                    }
                }

                // Converted audio
                if viewModel.convertedAudioData != nil {
                    PlaybackButton(
                        title: "转换后",
                        icon: "waveform.badge.plus",
                        isPlaying: viewModel.isPlayingConverted,
                        color: .green
                    ) {
                        if viewModel.isPlayingConverted {
                            viewModel.stopPlayback()
                        } else {
                            viewModel.playConverted()
                        }
                    }
                } else if viewModel.isConverting {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("转换中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }

            // Add to voice pack button
            if viewModel.convertedAudioData != nil {
                Button(action: {
                    newEntryName = "转换_\(viewModel.selectedModel?.name ?? "voice")"
                    showAddToPackAlert = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("添加到语音包")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - Add to Voice Pack

    private func addToVoicePack() {
        guard let wavData = viewModel.convertedAudioData else { return }

        Task {
            do {
                let silkData = try await convertWavToSilk(wavData: wavData)

                var finalName = newEntryName.isEmpty ? "转换语音" : newEntryName
                var counter = 1
                while voiceManager.entries.contains(where: { $0.name == finalName }) {
                    finalName = "\(newEntryName)_\(counter)"
                    counter += 1
                }

                let entry = AudioEntry(name: finalName, silkData: silkData)
                await MainActor.run {
                    voiceManager.entries.append(entry)
                    voiceManager.isModified = true
                    viewModel.statusMessage = "已添加到语音包: \(finalName)"
                    selectedTab = 0
                }
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = "添加失败: \(error.localizedDescription)"
                    viewModel.showError = true
                }
            }
        }
    }

    private func convertWavToSilk(wavData: Data) async throws -> Data {
        let tempWavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("temp_\(UUID().uuidString).wav")
        try wavData.write(to: tempWavURL)
        defer { try? FileManager.default.removeItem(at: tempWavURL) }
        return try await AudioConverter.audioToSilk(from: tempWavURL)
    }

    // MARK: - Recording Section

    private var recordingSection: some View {
        VStack(spacing: 0) {
            if viewModel.isRecording {
                recordingOverlay
            }

            WeChatRecordButton(
                isRecording: viewModel.isRecording,
                isDisabled: !viewModel.isServerAvailable || viewModel.selectedModel == nil || viewModel.isConverting,
                onStart: { viewModel.startRecording() },
                onEnd: { viewModel.stopRecording() },
                onCancel: { viewModel.cancelRecording() }
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(
            Color(.secondarySystemGroupedBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -4)
        )
    }

    private var recordingOverlay: some View {
        VStack(spacing: 12) {
            // Animated recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(0.9)

                Text(viewModel.formattedDuration)
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }

            Text("松开发送，上滑取消")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Model Picker Sheet

    private var modelPickerSheet: some View {
        NavigationView {
            List {
                ForEach(viewModel.models) { model in
                    Button(action: {
                        viewModel.selectedModel = model
                        showModelPicker = false
                    }) {
                        HStack(spacing: 12) {
                            // Model icon
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)

                                Text(String(model.name.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                HStack(spacing: 8) {
                                    Text(String(format: "%.1f MB", model.size_mb))
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    if model.has_index {
                                        Label("索引", systemImage: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                }
                            }

                            Spacer()

                            if viewModel.selectedModel?.id == model.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        showModelPicker = false
                    }
                }
            }
        }
    }
}

// MARK: - Playback Button

struct PlaybackButton: View {
    let title: String
    let icon: String
    let isPlaying: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isPlaying ? color : color.opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isPlaying ? .white : color)
                }

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isPlaying ? color : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
}

// MARK: - WeChat Style Record Button

struct WeChatRecordButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let onStart: () -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

    @State private var isCancelling = false
    private let cancelThreshold: CGFloat = -50

    var body: some View {
        VStack(spacing: 0) {
            if isRecording && isCancelling {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("松开取消")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red)
                .cornerRadius(8, corners: [.topLeft, .topRight])
            }

            HStack(spacing: 8) {
                if !isRecording && !isDisabled {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Text(buttonText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(textColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(backgroundColor)
            .cornerRadius(isCancelling ? 0 : 12)
            .cornerRadius(isCancelling ? 8 : 12, corners: isCancelling ? [.bottomLeft, .bottomRight] : .allCorners)
            .gesture(
                LongPressGesture(minimumDuration: 0.1)
                    .onEnded { _ in
                        if !isDisabled && !isRecording {
                            onStart()
                        }
                    }
                    .simultaneously(with:
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if isRecording {
                                    isCancelling = value.translation.height < cancelThreshold
                                }
                            }
                            .onEnded { _ in
                                if isRecording {
                                    if isCancelling {
                                        onCancel()
                                    } else {
                                        onEnd()
                                    }
                                }
                                isCancelling = false
                            }
                    )
            )
            .disabled(isDisabled)
            .animation(.easeInOut(duration: 0.15), value: isRecording)
            .animation(.easeInOut(duration: 0.15), value: isCancelling)
        }
    }

    private var buttonText: String {
        if isDisabled {
            return "请先选择模型"
        } else if isRecording {
            return isCancelling ? "松开取消" : "松开 发送"
        } else {
            return "按住 说话"
        }
    }

    private var textColor: Color {
        if isDisabled {
            return .secondary
        } else if isCancelling {
            return .white
        } else if isRecording {
            return .primary
        } else {
            return .primary
        }
    }

    private var backgroundColor: Color {
        if isCancelling {
            return Color.red
        } else if isRecording {
            return Color(.systemGray4)
        } else {
            return Color(.systemGray5)
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    VoiceConvertView()
}

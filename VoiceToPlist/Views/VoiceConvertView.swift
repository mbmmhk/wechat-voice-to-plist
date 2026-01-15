//
//  VoiceConvertView.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/2.
//

import SwiftUI
import UniformTypeIdentifiers

struct VoiceConvertView: View {
    @StateObject private var viewModel = VoiceConvertViewModel()
    @ObservedObject var voiceManager: VoiceManagerViewModel
    @Binding var selectedTab: Int
    @State private var showModelPicker = false
    @State private var showAddToPackAlert = false
    @State private var newEntryName = ""
    @State private var showAdvancedSettings = false
    @State private var modelSearchText = ""
    @State private var showServerPicker = false
    @State private var showAddServerSheet = false
    @State private var newServerName = ""
    @State private var newServerURL = ""
    @State private var showFilePicker = false
    @State private var showVideoPicker = false
    @State private var showModel2Picker = false  // For second model in blend mode
    @ObservedObject private var serverManager = RVCServerManager.shared
    @AppStorage("favoriteModels") private var favoriteModelsData: Data = Data()
    @AppStorage("recentModels") private var recentModelsData: Data = Data()

    private var favoriteModelNames: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: favoriteModelsData)) ?? []
        }
    }

    private var recentModelNames: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: recentModelsData)) ?? []
        }
    }

    private func toggleFavorite(_ modelName: String) {
        var favorites = favoriteModelNames
        if favorites.contains(modelName) {
            favorites.remove(modelName)
        } else {
            favorites.insert(modelName)
        }
        favoriteModelsData = (try? JSONEncoder().encode(favorites)) ?? Data()
    }

    private func addToRecent(_ modelName: String) {
        var recents = recentModelNames
        recents.removeAll { $0 == modelName }
        recents.insert(modelName, at: 0)
        if recents.count > 5 {
            recents = Array(recents.prefix(5))
        }
        recentModelsData = (try? JSONEncoder().encode(recents)) ?? Data()
    }

    init(voiceManager: VoiceManagerViewModel? = nil, selectedTab: Binding<Int>? = nil) {
        self._voiceManager = ObservedObject(wrappedValue: voiceManager ?? VoiceManagerViewModel())
        self._selectedTab = selectedTab ?? .constant(1)
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Color(.systemGroupedBackground),
                        Color(.systemGroupedBackground).opacity(0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Server status card
                            serverStatusCard
                                .padding(.top, 8)

                            // Model selection card
                            modelSelectionCard

                            // Parameters card (collapsible)
                            parametersCard

                            // Playback section (if audio available)
                            if viewModel.recordedAudioData != nil || viewModel.convertedAudioData != nil {
                                playbackCard
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }

                            // Noise recording card (separate, more prominent)
                            if viewModel.convertedAudioData != nil {
                                noiseRecordingCard
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }

                            Spacer(minLength: 120)
                        }
                        .padding(.horizontal, 16)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.convertedAudioData != nil)
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
                            .rotationEffect(.degrees(viewModel.isLoadingModels ? 360 : 0))
                            .animation(viewModel.isLoadingModels ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoadingModels)
                    }
                    .disabled(viewModel.isLoadingModels)
                }
            }
            .sheet(isPresented: $showModelPicker) {
                modelPickerSheet
            }
            .sheet(isPresented: $showModel2Picker) {
                model2PickerSheet
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
        VStack(spacing: 12) {
            // Server selector button
            Button(action: { showServerPicker = true }) {
                HStack(spacing: 12) {
                    // Status indicator
                    ZStack {
                        if viewModel.isServerAvailable {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 36, height: 36)
                                .scaleEffect(1.2)
                                .opacity(0)
                                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: viewModel.isServerAvailable)
                        }

                        Circle()
                            .fill(viewModel.isServerAvailable ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Circle()
                            .fill(viewModel.isServerAvailable ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                            .shadow(color: (viewModel.isServerAvailable ? Color.green : Color.red).opacity(0.5), radius: 3)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(serverManager.selectedServer.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }

                        Text(viewModel.isServerAvailable ? "已连接" : "未连接")
                            .font(.caption)
                            .foregroundColor(viewModel.isServerAvailable ? .green : .red)
                    }

                    Spacer()

                    if viewModel.isLoadingModels || viewModel.isConverting {
                        ZStack {
                            Circle()
                                .stroke(Color.blue.opacity(0.2), lineWidth: 3)
                                .frame(width: 26, height: 26)

                            Circle()
                                .trim(from: 0, to: 0.7)
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 26, height: 26)
                                .rotationEffect(.degrees(-90))
                        }
                    } else {
                        Image(systemName: "server.rack")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Status message
            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
        .sheet(isPresented: $showServerPicker) {
            serverPickerSheet
        }
    }

    // MARK: - Model Selection Card

    private var modelSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("声音模型", systemImage: "person.wave.2.fill")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Blend mode toggle
                HStack(spacing: 6) {
                    Text("融合")
                        .font(.caption)
                        .foregroundColor(viewModel.isBlendMode ? .blue : .secondary)
                    Toggle("", isOn: $viewModel.isBlendMode)
                        .labelsHidden()
                        .scaleEffect(0.8)
                        .tint(.blue)
                }

                if !viewModel.models.isEmpty {
                    Text("\(viewModel.models.count) 个可用")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(6)
                }
            }

            // Model 1 selector
            modelSelectorButton(
                model: viewModel.selectedModel,
                label: viewModel.isBlendMode ? "模型 A" : nil,
                action: { showModelPicker = true }
            )

            // Model 2 selector (only in blend mode)
            if viewModel.isBlendMode {
                modelSelectorButton(
                    model: viewModel.selectedModel2,
                    label: "模型 B",
                    action: { showModel2Picker = true }
                )

                // Blend ratio slider
                VStack(spacing: 8) {
                    HStack {
                        Text("融合比例")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "A %.0f%% : B %.0f%%",
                                   viewModel.blendRatio * 100,
                                   (1 - viewModel.blendRatio) * 100))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }

                    HStack(spacing: 12) {
                        Text("B")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)

                        Slider(value: $viewModel.blendRatio, in: 0...1, step: 0.05)
                            .tint(LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))

                        Text("A")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isBlendMode)
    }

    private func modelSelectorButton(model: RVCService.VoiceModel?, label: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Model icon with gradient
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: model != nil ?
                                [Color.blue, Color.purple] :
                                [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 48, height: 48)

                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 4) {
                    if let labelText = label {
                        Text(labelText)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }

                    // 显示中文名
                    Text(model?.display_name ?? "选择一个模型")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(model != nil ? .primary : .secondary)

                    if viewModel.isLoadingModels {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("加载中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let m = model {
                        HStack(spacing: 8) {
                            // 文件名（如果与显示名不同）
                            if m.name != m.display_name {
                                Text(m.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            // 版本和采样率信息
                            if !m.versionInfo.isEmpty {
                                Text(m.versionInfo)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(4)
                            }

                            Text(String(format: "%.1f MB", m.size_mb))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if m.has_index {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                    Text("索引")
                                }
                                .font(.caption2)
                                .foregroundColor(.green)
                            }
                        }
                    } else {
                        Text("点击选择声音模型")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Circle())
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(model != nil ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .disabled(viewModel.models.isEmpty)
    }

    // MARK: - Parameters Card

    private var parametersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("转换参数", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Reset button
                Button(action: resetParameters) {
                    Text("重置")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            VStack(spacing: 16) {
                // Main parameters (always visible)
                // Pitch - most important
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "music.note")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.orange)
                        }

                        Text("音高调整")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer()

                        // Value badge
                        Text("\(Int(viewModel.pitch)) 半音")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(8)
                    }

                    // Slider with tick marks
                    VStack(spacing: 4) {
                        Slider(value: $viewModel.pitch, in: -12...12, step: 1)
                            .tint(.orange)

                        // Tick marks
                        GeometryReader { geometry in
                            let tickCount = 25 // -12 to 12
                            let spacing = geometry.size.width / CGFloat(tickCount - 1)

                            ZStack(alignment: .top) {
                                // Tick lines
                                HStack(spacing: 0) {
                                    ForEach(-12...12, id: \.self) { value in
                                        VStack(spacing: 2) {
                                            Rectangle()
                                                .fill(value == 0 ? Color.orange : Color(.systemGray4))
                                                .frame(width: value % 4 == 0 ? 2 : 1, height: value % 4 == 0 ? 8 : 5)

                                            if value % 4 == 0 {
                                                Text("\(value)")
                                                    .font(.system(size: 9, weight: value == 0 ? .bold : .regular))
                                                    .foregroundColor(value == 0 ? .orange : .secondary)
                                            }
                                        }
                                        if value < 12 {
                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(height: 22)
                    }

                    HStack {
                        Text("女→男")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("男→女")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(12)

                // F0 Method
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "waveform.path")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.purple)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("F0提取方法")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text(f0MethodDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Picker("", selection: $viewModel.f0Method) {
                        ForEach(VoiceConvertViewModel.f0Methods, id: \.self) { method in
                            Text(method.uppercased()).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(14)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(12)

                // Advanced settings toggle
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showAdvancedSettings.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: "gearshape.2")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("高级参数")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Spacer()

                        Text(showAdvancedSettings ? "收起" : "展开")
                            .font(.caption)
                            .foregroundColor(.blue)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees(showAdvancedSettings ? 180 : 0))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(10)
                }

                // Advanced parameters (collapsible)
                if showAdvancedSettings {
                    VStack(spacing: 14) {
                        // Index Rate
                        compactParameterRow(
                            icon: "person.fill.viewfinder",
                            iconColor: .blue,
                            title: "音色相似度",
                            value: String(format: "%.0f%%", viewModel.indexRate * 100),
                            hint: "越高越像目标音色"
                        ) {
                            Slider(value: $viewModel.indexRate, in: 0...1, step: 0.1)
                                .tint(.blue)
                        }

                        // Filter Radius
                        compactParameterRow(
                            icon: "circle.hexagongrid",
                            iconColor: .cyan,
                            title: "中值滤波",
                            value: "\(Int(viewModel.filterRadius))",
                            hint: "平滑音质"
                        ) {
                            Slider(value: $viewModel.filterRadius, in: 0...7, step: 1)
                                .tint(.cyan)
                        }

                        // RMS Mix Rate
                        compactParameterRow(
                            icon: "speaker.wave.2",
                            iconColor: .indigo,
                            title: "音量包络",
                            value: String(format: "%.0f%%", viewModel.rmsMixRate * 100),
                            hint: "混合音量变化"
                        ) {
                            Slider(value: $viewModel.rmsMixRate, in: 0...1, step: 0.05)
                                .tint(.indigo)
                        }

                        // Protect
                        compactParameterRow(
                            icon: "shield.fill",
                            iconColor: .green,
                            title: "辅音保护",
                            value: String(format: "%.0f%%", viewModel.protect * 200),
                            hint: "减少电音感"
                        ) {
                            Slider(value: $viewModel.protect, in: 0...0.5, step: 0.05)
                                .tint(.green)
                        }
                    }
                    .padding(14)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(12)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
    }

    private var f0MethodDescription: String {
        switch viewModel.f0Method {
        case "rmvpe": return "推荐，效果最好"
        case "crepe": return "更精准但较慢"
        case "harvest": return "传统方法"
        case "pm": return "最快但质量一般"
        default: return ""
        }
    }

    private func resetParameters() {
        withAnimation {
            viewModel.pitch = 0
            viewModel.f0Method = "rmvpe"
            viewModel.indexRate = 0.5
            viewModel.filterRadius = 3
            viewModel.rmsMixRate = 0.25
            viewModel.protect = 0.33
        }
    }

    private func compactParameterRow<Content: View>(
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 18)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)

                Text("·")
                    .foregroundColor(.secondary)

                Text(hint)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(iconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(iconColor.opacity(0.1))
                    .cornerRadius(5)
            }

            slider()
        }
    }

    // MARK: - Playback Card

    private var playbackCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("音频试听", systemImage: "headphones")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if viewModel.isConverting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("转换中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if viewModel.recordedAudioData != nil && viewModel.convertedAudioData != nil {
                    // Reconvert button
                    Button(action: {
                        Task {
                            await viewModel.reconvert()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .medium))
                            Text("重新转换")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }

            // Audio players - Original and Converted only
            HStack(spacing: 12) {
                // Original audio
                if viewModel.recordedAudioData != nil {
                    EnhancedPlaybackButton(
                        title: "原始录音",
                        subtitle: "录制的音频",
                        icon: "waveform",
                        isPlaying: viewModel.isPlayingOriginal,
                        color: .blue,
                        action: {
                            if viewModel.isPlayingOriginal {
                                viewModel.stopPlayback()
                            } else {
                                viewModel.playOriginal()
                            }
                        }
                    )
                }

                // Converted audio
                if viewModel.convertedAudioData != nil {
                    EnhancedPlaybackButton(
                        title: "转换后",
                        subtitle: viewModel.selectedModel?.name ?? "RVC",
                        icon: "waveform.badge.plus",
                        isPlaying: viewModel.isPlayingConverted,
                        color: .green,
                        action: {
                            if viewModel.isPlayingConverted {
                                viewModel.stopPlayback()
                            } else {
                                viewModel.playConverted()
                            }
                        }
                    )
                } else if viewModel.isConverting {
                    // Converting placeholder
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.green.opacity(0.2), lineWidth: 4)
                                .frame(width: 56, height: 56)

                            Circle()
                                .trim(from: 0, to: 0.7)
                                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 56, height: 56)
                                .rotationEffect(.degrees(-90))
                        }

                        Text("转换中...")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(14)
                }
            }

            // Add converted audio to voice pack button
            if viewModel.convertedAudioData != nil {
                Button(action: {
                    addConvertedToVoicePack()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))

                        Text("添加转换音频到语音包")
                            .fontWeight(.medium)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: Color.green.opacity(0.3), radius: 6, x: 0, y: 3)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: - Noise Recording Card (Separate)

    private var noiseRecordingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("底噪混合")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("录制环境音混入转换后的语音")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if viewModel.noiseAudioData != nil {
                    Button(action: { viewModel.clearNoise() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                            Text("清除")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }

            if viewModel.isRecordingNoise {
                // Recording in progress with waveform animation
                VStack(spacing: 16) {
                    // Waveform animation
                    HStack(spacing: 4) {
                        ForEach(0..<12, id: \.self) { index in
                            WaveformBar(index: index, isAnimating: true)
                        }
                    }
                    .frame(height: 40)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Color.red.opacity(0.3), lineWidth: 3)
                                    .scaleEffect(1.5)
                            )

                        Text(viewModel.formattedNoiseRecordingDuration)
                            .font(.system(size: 32, weight: .medium, design: .monospaced))

                        Text("/ \(viewModel.formattedRequiredDuration)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray5))
                                .frame(height: 8)

                            Capsule()
                                .fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geometry.size.width * CGFloat(viewModel.noiseRecordingDuration / max(1, viewModel.requiredNoiseDuration)), height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text("正在录制环境底噪...")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { viewModel.cancelNoiseRecording() }) {
                        HStack {
                            Image(systemName: "xmark")
                            Text("取消录制")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            } else if viewModel.noiseAudioData != nil {
                // Noise recorded - show controls
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        // Play noise button
                        Button(action: {
                            if viewModel.isPlayingNoise {
                                viewModel.stopPlayback()
                            } else {
                                viewModel.playNoise()
                            }
                        }) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(viewModel.isPlayingNoise ? Color.orange : Color.orange.opacity(0.15))
                                        .frame(width: 36, height: 36)

                                    Image(systemName: viewModel.isPlayingNoise ? "stop.fill" : "play.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(viewModel.isPlayingNoise ? .white : .orange)
                                }

                                Text(viewModel.isPlayingNoise ? "停止" : "试听底噪")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(12)
                        }

                        Spacer()

                        // Volume indicator
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text(String(format: "%.0f%%", viewModel.noiseVolume * 100))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Volume slider with icons
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.1")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))

                        Slider(value: Binding(
                            get: { Double(viewModel.noiseVolume) },
                            set: { viewModel.updateNoiseVolume(Float($0)) }
                        ), in: 0...2, step: 0.05)
                        .tint(.orange)

                        Image(systemName: "speaker.wave.3")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }

                    Text("调节底噪音量后自动重新混合")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(12)

                // Mixed audio playback (if available)
                if viewModel.mixedAudioData != nil {
                    HStack(spacing: 12) {
                        // Play mixed button
                        Button(action: {
                            if viewModel.isPlayingMixed {
                                viewModel.stopPlayback()
                            } else {
                                viewModel.playMixed()
                            }
                        }) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(viewModel.isPlayingMixed ? Color.purple : Color.purple.opacity(0.15))
                                        .frame(width: 40, height: 40)

                                    Image(systemName: viewModel.isPlayingMixed ? "stop.fill" : "play.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(viewModel.isPlayingMixed ? .white : .purple)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("混合后音频")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text("转换音频 + 底噪")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if viewModel.isPlayingMixed {
                                    // Waveform animation
                                    HStack(spacing: 2) {
                                        ForEach(0..<5, id: \.self) { index in
                                            WaveformBar(index: index, isAnimating: true, color: .purple)
                                        }
                                    }
                                    .frame(width: 30, height: 20)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.tertiarySystemGroupedBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(viewModel.isPlayingMixed ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 2)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Add mixed audio to voice pack button
                    Button(action: {
                        addMixedToVoicePack()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))

                            Text("添加混合音频到语音包")
                                .fontWeight(.medium)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(
                            LinearGradient(
                                colors: [Color.purple, Color.purple.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Color.purple.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                }
            } else {
                // No noise - show record button
                Button(action: { viewModel.startNoiseRecording() }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 44, height: 44)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.orange)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("录制底噪")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Text("需要录制 \(viewModel.formattedRequiredDuration)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(14)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: - Add to Voice Pack

    private func addConvertedToVoicePack() {
        guard let wavData = viewModel.convertedAudioData else { return }

        Task {
            do {
                let silkData = try await convertWavToSilk(wavData: wavData)

                let baseName = "转换_\(viewModel.selectedModel?.name ?? "voice")"
                let formattedName = voiceManager.formatNameWithDuration(originalName: baseName, silkData: silkData)

                var finalName = formattedName
                var counter = 1
                while voiceManager.entries.contains(where: { $0.name == finalName }) {
                    finalName = voiceManager.formatNameWithDuration(originalName: "\(baseName)_\(counter)", silkData: silkData)
                    counter += 1
                }

                let entry = AudioEntry(name: finalName, silkData: silkData)
                await MainActor.run {
                    voiceManager.entries.append(entry)
                    voiceManager.isModified = true
                    viewModel.statusMessage = "已添加转换音频: \(finalName)"
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

    private func addMixedToVoicePack() {
        guard let wavData = viewModel.mixedAudioData else { return }

        Task {
            do {
                let silkData = try await convertWavToSilk(wavData: wavData)

                let baseName = "混合_\(viewModel.selectedModel?.name ?? "voice")"
                let formattedName = voiceManager.formatNameWithDuration(originalName: baseName, silkData: silkData)

                var finalName = formattedName
                var counter = 1
                while voiceManager.entries.contains(where: { $0.name == finalName }) {
                    finalName = voiceManager.formatNameWithDuration(originalName: "\(baseName)_\(counter)", silkData: silkData)
                    counter += 1
                }

                let entry = AudioEntry(name: finalName, silkData: silkData)
                await MainActor.run {
                    voiceManager.entries.append(entry)
                    voiceManager.isModified = true
                    viewModel.statusMessage = "已添加混合音频: \(finalName)"
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

    private func addToVoicePack() {
        // Use mixed audio if available, otherwise use converted audio
        guard let wavData = viewModel.mixedAudioData ?? viewModel.convertedAudioData else { return }

        Task {
            do {
                let silkData = try await convertWavToSilk(wavData: wavData)

                var baseName = newEntryName.isEmpty ? "转换语音" : newEntryName
                // Format name with duration prefix
                let formattedName = voiceManager.formatNameWithDuration(originalName: baseName, silkData: silkData)

                // Check for duplicates with the formatted name
                var finalName = formattedName
                var counter = 1
                while voiceManager.entries.contains(where: { $0.name == finalName }) {
                    finalName = voiceManager.formatNameWithDuration(originalName: "\(baseName)_\(counter)", silkData: silkData)
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

            VStack(spacing: 12) {
                // Import buttons row
                HStack(spacing: 12) {
                    // Import from file button
                    Button(action: { showFilePicker = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("导入音频")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(importButtonsDisabled ? .secondary : .blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.blue.opacity(importButtonsDisabled ? 0.05 : 0.1))
                        .cornerRadius(10)
                    }
                    .disabled(importButtonsDisabled)

                    // Import from photo library button
                    Button(action: { showVideoPicker = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("导入视频")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(importButtonsDisabled ? .secondary : .purple)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.purple.opacity(importButtonsDisabled ? 0.05 : 0.1))
                        .cornerRadius(10)
                    }
                    .disabled(importButtonsDisabled)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Record button
                EnhancedRecordButton(
                    isRecording: viewModel.isRecording,
                    isDisabled: importButtonsDisabled,
                    duration: viewModel.recordingDuration,
                    onStart: { viewModel.startRecording() },
                    onEnd: { viewModel.stopRecording() },
                    onCancel: { viewModel.cancelRecording() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(
            Color(.secondarySystemGroupedBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: -6)
        )
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showVideoPicker) {
            PhotoPickerView { urls in
                if let url = urls.first {
                    Task {
                        await viewModel.importAudio(from: url)
                    }
                }
            }
        }
    }

    private var importButtonsDisabled: Bool {
        !viewModel.isServerAvailable || viewModel.selectedModel == nil || viewModel.isConverting
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                Task {
                    await viewModel.importAudio(from: url)
                }
            }
        case .failure(let error):
            viewModel.errorMessage = "选择文件失败: \(error.localizedDescription)"
            viewModel.showError = true
        }
    }

    private var recordingOverlay: some View {
        VStack(spacing: 16) {
            // Waveform animation
            HStack(spacing: 3) {
                ForEach(0..<16, id: \.self) { index in
                    WaveformBar(index: index, isAnimating: viewModel.isRecording, color: .blue)
                }
            }
            .frame(height: 50)

            // Duration display
            HStack(spacing: 10) {
                // Pulsing record indicator
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .scaleEffect(viewModel.isRecording ? 1.3 : 1)
                        .opacity(viewModel.isRecording ? 0 : 0.5)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: false), value: viewModel.isRecording)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 14, height: 14)
                }

                Text(viewModel.formattedDuration)
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }

            Text("松开发送，上滑取消")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            LinearGradient(
                colors: [Color(.systemGroupedBackground), Color(.systemGroupedBackground).opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Server Picker Sheet

    private var serverPickerSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Preset servers section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.yellow)
                            Text("预设服务器")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        ForEach(RVCServer.presetServers) { server in
                            serverRow(server: server, isSelected: serverManager.selectedServer.id == server.id)
                        }
                    }

                    // Custom servers section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                            Text("自定义服务器")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()

                            Button(action: {
                                newServerName = ""
                                newServerURL = ""
                                showAddServerSheet = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("添加")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 4)

                        if serverManager.customServers.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "server.rack")
                                        .font(.system(size: 32))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("暂无自定义服务器")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 20)
                                Spacer()
                            }
                            .background(Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(12)
                        } else {
                            ForEach(serverManager.customServers) { server in
                                serverRow(server: server, isSelected: serverManager.selectedServer.id == server.id)
                                    .contextMenu {
                                        Button(role: .destructive, action: {
                                            serverManager.removeCustomServer(server)
                                        }) {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("选择服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") {
                        showServerPicker = false
                        // Refresh models after server change
                        Task {
                            await viewModel.refreshModels()
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddServerSheet) {
                addServerSheet
            }
        }
    }

    private func serverRow(server: RVCServer, isSelected: Bool) -> some View {
        Button(action: {
            serverManager.selectServer(server)
        }) {
            HStack(spacing: 14) {
                // Server icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color(.tertiarySystemGroupedBackground))
                        .frame(width: 44, height: 44)

                    Image(systemName: server.isPreset ? "building.2.fill" : "server.rack")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isSelected ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(server.url)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var addServerSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("服务器名称", text: $newServerName)
                        .textContentType(.name)

                    TextField("服务器地址", text: $newServerURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("服务器信息")
                } footer: {
                    Text("请输入完整的服务器地址，例如：https://example.com:8443")
                }

                Section {
                    Button(action: {
                        let server = serverManager.addCustomServer(name: newServerName, url: newServerURL)
                        serverManager.selectServer(server)
                        showAddServerSheet = false
                        Task {
                            await viewModel.refreshModels()
                        }
                    }) {
                        HStack {
                            Spacer()
                            Text("添加并使用")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(newServerName.isEmpty || newServerURL.isEmpty)
                }
            }
            .navigationTitle("添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        showAddServerSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Model Picker Sheet

    private var modelPickerSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))

                        TextField("搜索模型...", text: $modelSearchText)
                            .textFieldStyle(.plain)

                        if !modelSearchText.isEmpty {
                            Button(action: { modelSearchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))

                ScrollView {
                    VStack(spacing: 0) {
                        // Favorites section
                        if !filteredFavoriteModels.isEmpty && modelSearchText.isEmpty {
                            sectionHeader(title: "收藏", icon: "star.fill", color: .yellow, count: filteredFavoriteModels.count)
                                .padding(.horizontal, 16)

                            VStack(spacing: 0) {
                                ForEach(filteredFavoriteModels) { model in
                                    modelRow(model: model, isFavorite: true)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }

                        // Recent section
                        if !filteredRecentModels.isEmpty && modelSearchText.isEmpty {
                            sectionHeader(title: "最近使用", icon: "clock.fill", color: .blue, count: filteredRecentModels.count)
                                .padding(.horizontal, 16)

                            VStack(spacing: 0) {
                                ForEach(filteredRecentModels) { model in
                                    modelRow(model: model, isFavorite: favoriteModelNames.contains(model.name))
                                        .padding(.horizontal, 16)
                                }
                            }
                        }

                        // All models section
                        sectionHeader(
                            title: modelSearchText.isEmpty ? "全部模型" : "搜索结果",
                            icon: modelSearchText.isEmpty ? "waveform.circle.fill" : "magnifyingglass",
                            color: .purple,
                            count: filteredModels.count
                        )
                        .padding(.horizontal, 16)

                        LazyVStack(spacing: 0) {
                            ForEach(filteredModels) { model in
                                modelRow(model: model, isFavorite: favoriteModelNames.contains(model.name))
                                    .padding(.horizontal, 16)
                            }
                        }

                        if filteredModels.isEmpty && modelSearchText.isEmpty == false {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("没有找到匹配的模型")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        modelSearchText = ""
                        showModelPicker = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(viewModel.models.count) 个模型")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onDisappear {
            modelSearchText = ""
        }
    }

    // MARK: - Model 2 Picker Sheet (for blend mode)

    private var model2PickerSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))

                        TextField("搜索模型...", text: $modelSearchText)
                            .textFieldStyle(.plain)

                        if !modelSearchText.isEmpty {
                            Button(action: { modelSearchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))

                ScrollView {
                    VStack(spacing: 0) {
                        // 兼容组提示
                        if let blendGroup = viewModel.selectedModel?.blend_group {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 14))
                                Text("仅显示可融合的模型（\(blendGroup)）")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.1))
                        }

                        // All models section (simplified for model 2)
                        sectionHeader(
                            title: modelSearchText.isEmpty ? "可融合模型" : "搜索结果",
                            icon: "waveform.circle.fill",
                            color: .purple,
                            count: filteredModelsForModel2.count
                        )
                        .padding(.horizontal, 16)

                        LazyVStack(spacing: 0) {
                            ForEach(filteredModelsForModel2) { model in
                                model2Row(model: model)
                                    .padding(.horizontal, 16)
                            }
                        }

                        if filteredModelsForModel2.isEmpty && !modelSearchText.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("没有找到匹配的模型")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }

                        if filteredModelsForModel2.isEmpty && modelSearchText.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.orange)
                                Text("没有可融合的模型")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("请选择其他模型 A，或确保有相同网络结构的模型")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("选择模型 B")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        modelSearchText = ""
                        showModel2Picker = false
                    }
                }
            }
        }
        .onDisappear {
            modelSearchText = ""
        }
    }

    private var filteredModelsForModel2: [RVCService.VoiceModel] {
        // 只显示与模型1兼容的模型（相同 blend_group）
        let compatibleModels = viewModel.compatibleModelsForBlend
        if modelSearchText.isEmpty {
            return compatibleModels
        }
        return compatibleModels.filter { model in
            model.name.localizedCaseInsensitiveContains(modelSearchText) ||
            model.display_name.localizedCaseInsensitiveContains(modelSearchText)
        }
    }

    private func model2Row(model: RVCService.VoiceModel) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.selectedModel2 = model
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                modelSearchText = ""
                showModel2Picker = false
            }
        }) {
            HStack(spacing: 14) {
                // Model avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: modelGradientColors(for: model.name),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Text(String(model.name.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.display_name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        // 文件名（如果与显示名不同）
                        if model.name != model.display_name {
                            Text(model.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // 版本和采样率
                        if !model.versionInfo.isEmpty {
                            Text(model.versionInfo)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }

                        Text(String(format: "%.1f MB", model.size_mb))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if model.has_index {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("索引")
                            }
                            .font(.caption2)
                            .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                // Selected indicator
                if viewModel.selectedModel2?.id == model.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredModels: [RVCService.VoiceModel] {
        if modelSearchText.isEmpty {
            return viewModel.models
        }
        return viewModel.models.filter { model in
            model.name.localizedCaseInsensitiveContains(modelSearchText)
        }
    }

    private var filteredFavoriteModels: [RVCService.VoiceModel] {
        viewModel.models.filter { favoriteModelNames.contains($0.name) }
    }

    private var filteredRecentModels: [RVCService.VoiceModel] {
        let recentNames = recentModelNames
        return recentNames.compactMap { name in
            viewModel.models.first { $0.name == name }
        }.filter { !favoriteModelNames.contains($0.name) } // Exclude favorites from recent
    }

    private func sectionHeader(title: String, icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text("(\(count))")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    private func modelRow(model: RVCService.VoiceModel, isFavorite: Bool) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.selectedModel = model
            }
            addToRecent(model.name)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                modelSearchText = ""
                showModelPicker = false
            }
        }) {
            HStack(spacing: 14) {
                // Model avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: modelGradientColors(for: model.name),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Text(String(model.name.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // 显示中文名
                    Text(model.display_name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // 文件名（如果与显示名不同）
                        if model.name != model.display_name {
                            Text(model.name)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        // 版本和采样率
                        if !model.versionInfo.isEmpty {
                            Text(model.versionInfo)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(3)
                        }

                        Text(String(format: "%.1f MB", model.size_mb))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if model.has_index {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8))
                                Text("索引")
                            }
                            .font(.caption2)
                            .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                // Favorite button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        toggleFavorite(model.name)
                    }
                }) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundColor(isFavorite ? .yellow : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)

                // Selection indicator
                if viewModel.selectedModel?.id == model.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.selectedModel?.id == model.id ? Color.blue.opacity(0.08) : Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private func modelGradientColors(for name: String) -> [Color] {
        let hash = abs(name.hashValue)
        let colorSets: [[Color]] = [
            [.blue, .purple],
            [.orange, .pink],
            [.green, .teal],
            [.indigo, .blue],
            [.pink, .red],
            [.teal, .cyan],
            [.purple, .indigo]
        ]
        return colorSets[hash % colorSets.count]
    }
}

// MARK: - Enhanced Playback Button

struct EnhancedPlaybackButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isPlaying: Bool
    let color: Color
    let action: () -> Void

    @State private var wavePhase: CGFloat = 0

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    // Background circle with gradient
                    Circle()
                        .fill(
                            isPlaying ?
                                LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient(colors: [color.opacity(0.12), color.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 56, height: 56)

                    // Pulse effect when playing
                    if isPlaying {
                        Circle()
                            .stroke(color.opacity(0.3), lineWidth: 2)
                            .frame(width: 56, height: 56)
                            .scaleEffect(isPlaying ? 1.3 : 1)
                            .opacity(isPlaying ? 0 : 1)
                            .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: isPlaying)
                    }

                    // Icon
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isPlaying ? .white : color)
                }
                .shadow(color: isPlaying ? color.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isPlaying ? color : .primary)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isPlaying ? color.opacity(0.4) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Waveform Bar Animation

struct WaveformBar: View {
    let index: Int
    let isAnimating: Bool
    var color: Color = .orange

    @State private var height: CGFloat = 0.3

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(0.7))
            .frame(width: 4, height: isAnimating ? height * 40 : 8)
            .animation(
                isAnimating ?
                    Animation.easeInOut(duration: Double.random(in: 0.3...0.6))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.05) :
                    .default,
                value: isAnimating
            )
            .onAppear {
                if isAnimating {
                    height = CGFloat.random(in: 0.3...1.0)
                }
            }
            .onChange(of: isAnimating) { newValue in
                if newValue {
                    withAnimation {
                        height = CGFloat.random(in: 0.3...1.0)
                    }
                }
            }
    }
}

// MARK: - Enhanced Record Button

struct EnhancedRecordButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let duration: TimeInterval
    let onStart: () -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

    @State private var isCancelling = false
    @State private var pulseScale: CGFloat = 1
    private let cancelThreshold: CGFloat = -50

    var body: some View {
        VStack(spacing: 0) {
            // Cancel indicator
            if isRecording && isCancelling {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                    Text("松开取消")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.red, .red.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(12, corners: [.topLeft, .topRight])
            }

            // Main button
            HStack(spacing: 12) {
                // Mic icon with animation
                if !isRecording && !isDisabled {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 36, height: 36)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }

                Text(buttonText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(textColor)

                if isRecording && !isCancelling {
                    // Waveform indicator when recording
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            WaveformBar(index: index, isAnimating: isRecording, color: .blue)
                        }
                    }
                    .frame(width: 30, height: 20)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(backgroundColor)
            .cornerRadius(isCancelling ? 0 : 14)
            .cornerRadius(isCancelling ? 12 : 14, corners: isCancelling ? [.bottomLeft, .bottomRight] : .allCorners)
            .overlay(
                RoundedRectangle(cornerRadius: isCancelling ? 12 : 14)
                    .stroke(isRecording && !isCancelling ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isRecording ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
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
            return .blue
        } else {
            return .primary
        }
    }

    private var backgroundColor: some ShapeStyle {
        if isCancelling {
            return AnyShapeStyle(Color.red)
        } else if isRecording {
            return AnyShapeStyle(Color.blue.opacity(0.08))
        } else {
            return AnyShapeStyle(Color(.systemGray5))
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

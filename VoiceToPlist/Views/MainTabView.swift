//
//  MainTabView.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/2.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @StateObject private var voiceManager = VoiceManagerViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Voice Manager (existing functionality)
            ContentView(viewModel: voiceManager)
                .tabItem {
                    Image(systemName: "waveform.circle")
                    Text("语音包")
                }
                .tag(0)

            // Tab 2: Voice Conversion
            VoiceConvertView(voiceManager: voiceManager, selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "mic.badge.plus")
                    Text("语音转换")
                }
                .tag(1)
        }
    }
}

#Preview {
    MainTabView()
}

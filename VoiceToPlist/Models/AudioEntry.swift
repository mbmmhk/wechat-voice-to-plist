//
//  AudioEntry.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/1.
//

import Foundation

/// Represents a single audio entry in the plist file
struct AudioEntry: Identifiable, Hashable {
    let id: UUID
    var name: String
    var silkData: Data  // Raw SILK audio data (decoded from base64)
    private var _duration: TimeInterval?

    init(id: UUID = UUID(), name: String, silkData: Data) {
        self.id = id
        self.name = name
        self.silkData = silkData
        self._duration = nil
    }

    /// Check if the data is valid SILK format
    var isValidSilk: Bool {
        // SILK magic bytes: \x02#!SILK_V3
        guard silkData.count > 10 else { return false }
        let header = silkData.prefix(10)
        return header.starts(with: [0x02, 0x23, 0x21, 0x53, 0x49, 0x4C, 0x4B, 0x5F, 0x56, 0x33])
    }

    /// Get the duration of the audio in seconds
    /// Calculates from PCM data: duration = samples / sampleRate
    /// PCM format: 16-bit (2 bytes per sample), 24kHz, mono
    var duration: TimeInterval {
        if let cached = _duration {
            return cached
        }

        guard isValidSilk else { return 0 }

        do {
            let pcmData = try SilkCodec.decode(silkData)
            // 16-bit = 2 bytes per sample, 24000 samples per second
            let samples = pcmData.count / 2
            let duration = Double(samples) / 24000.0
            return duration
        } catch {
            return 0
        }
    }

    /// Formatted duration string (e.g., "0:05" or "1:23")
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Short formatted duration (e.g., "5秒" or "1分23秒")
    var shortDuration: String {
        let totalSeconds = Int(round(duration))
        if totalSeconds < 60 {
            return "\(totalSeconds)″"
        } else {
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            if seconds == 0 {
                return "\(minutes)′"
            }
            return "\(minutes)′\(seconds)″"
        }
    }
}

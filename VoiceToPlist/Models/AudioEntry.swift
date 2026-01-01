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

    init(id: UUID = UUID(), name: String, silkData: Data) {
        self.id = id
        self.name = name
        self.silkData = silkData
    }

    /// Check if the data is valid SILK format
    var isValidSilk: Bool {
        // SILK magic bytes: \x02#!SILK_V3
        guard silkData.count > 10 else { return false }
        let header = silkData.prefix(10)
        return header.starts(with: [0x02, 0x23, 0x21, 0x53, 0x49, 0x4C, 0x4B, 0x5F, 0x56, 0x33])
    }
}

//
//  SilkCodec.swift
//  VoiceToPlist
//
//  SILK audio codec wrapper for iOS
//  Uses the native SILK C library via Objective-C bridge
//

import Foundation
import AVFoundation

/// SILK audio codec wrapper
class SilkCodec {

    enum SilkError: LocalizedError {
        case invalidSilkData
        case decodeFailed
        case encodeFailed
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .invalidSilkData:
                return "Invalid SILK audio data"
            case .decodeFailed:
                return "Failed to decode SILK audio"
            case .encodeFailed:
                return "Failed to encode to SILK format"
            case .unsupportedFormat:
                return "Unsupported audio format"
            }
        }
    }

    /// SILK magic bytes: #!SILK_V3 (with 0x02 prefix for Tencent variant)
    static let silkMagic: [UInt8] = [0x02, 0x23, 0x21, 0x53, 0x49, 0x4C, 0x4B, 0x5F, 0x56, 0x33]

    /// Standard SILK magic without Tencent prefix
    static let standardSilkMagic: [UInt8] = [0x23, 0x21, 0x53, 0x49, 0x4C, 0x4B, 0x5F, 0x56, 0x33]

    /// Default sample rate for SILK audio
    static let defaultSampleRate: Int32 = 24000

    /// Check if data is valid SILK format
    static func isValidSilk(_ data: Data) -> Bool {
        guard data.count > 10 else { return false }
        let header = Array(data.prefix(10))

        // Check for Tencent SILK (with 0x02 prefix)
        if header == silkMagic {
            return true
        }

        // Check for standard SILK
        let header9 = Array(data.prefix(9))
        if header9 == standardSilkMagic {
            return true
        }

        return false
    }

    /// Decode SILK data to PCM
    /// - Parameter silkData: Raw SILK audio data
    /// - Returns: PCM audio data (16-bit, 24kHz, mono)
    static func decode(_ silkData: Data) throws -> Data {
        guard isValidSilk(silkData) else {
            throw SilkError.invalidSilkData
        }

        // Use native SILK decoder via Objective-C bridge
        guard let pcmData = SilkWrapper.decodeSilk(toPCM: silkData, sampleRate: defaultSampleRate) else {
            throw SilkError.decodeFailed
        }

        return pcmData
    }

    /// Encode PCM data to SILK format
    /// - Parameter pcmData: PCM audio data (16-bit, 24kHz, mono)
    /// - Returns: SILK encoded audio data
    static func encode(_ pcmData: Data) throws -> Data {
        // Use native SILK encoder via Objective-C bridge
        guard let silkData = SilkWrapper.encodePCM(toSilk: pcmData, sampleRate: defaultSampleRate) else {
            throw SilkError.encodeFailed
        }

        return silkData
    }

    /// Convert SILK data to WAV format for playback
    /// - Parameter silkData: Raw SILK audio data
    /// - Returns: WAV audio data
    static func silkToWav(_ silkData: Data) throws -> Data {
        let pcmData = try decode(silkData)
        return createWavFile(from: pcmData, sampleRate: Int(defaultSampleRate), channels: 1, bitsPerSample: 16)
    }

    /// Create WAV file from PCM data
    private static func createWavFile(from pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var wav = Data()

        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = pcmData.count
        let fileSize = 36 + dataSize

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // audio format (PCM)
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data chunk
        wav.append(contentsOf: "data".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        wav.append(pcmData)

        return wav
    }
}

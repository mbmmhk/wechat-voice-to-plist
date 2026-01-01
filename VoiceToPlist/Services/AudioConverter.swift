//
//  AudioConverter.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/1.
//

import Foundation
import AVFoundation

/// Audio format conversion service using AVFoundation
class AudioConverter {

    enum ConversionError: LocalizedError {
        case fileNotFound
        case unsupportedFormat
        case conversionFailed(String)
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Audio file not found"
            case .unsupportedFormat:
                return "Unsupported audio format"
            case .conversionFailed(let message):
                return "Conversion failed: \(message)"
            case .exportFailed(let message):
                return "Export failed: \(message)"
            }
        }
    }

    /// Supported input formats
    static let supportedAudioFormats = ["mp3", "wav", "m4a", "aac", "ogg", "flac", "caf"]
    static let supportedVideoFormats = ["mp4", "mov", "m4v"]

    /// Convert audio file to PCM data (16-bit, 24kHz, mono)
    /// - Parameter url: URL of the source audio file
    /// - Returns: PCM data
    static func audioToPCM(from url: URL) async throws -> Data {
        let asset = AVAsset(url: url)

        // Get audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ConversionError.unsupportedFormat
        }

        // Create reader
        let reader = try AVAssetReader(asset: asset)

        // Output settings: 16-bit PCM, 24kHz, mono
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 24000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw ConversionError.conversionFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        var pcmData = Data()

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                var length = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

                if let dataPointer = dataPointer {
                    pcmData.append(UnsafeBufferPointer(start: dataPointer, count: length))
                }
            }
        }

        if reader.status == .failed {
            throw ConversionError.conversionFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        return pcmData
    }

    /// Convert audio file to SILK format
    /// - Parameter url: URL of the source audio file
    /// - Returns: SILK encoded data
    static func audioToSilk(from url: URL) async throws -> Data {
        let pcmData = try await audioToPCM(from: url)
        return try SilkCodec.encode(pcmData)
    }

    /// Export SILK data to audio file
    /// - Parameters:
    ///   - silkData: SILK encoded data
    ///   - format: Output format ("wav", "m4a")
    ///   - url: Destination URL
    static func exportSilk(_ silkData: Data, to format: String, at url: URL) async throws {
        let wavData = try SilkCodec.silkToWav(silkData)

        if format.lowercased() == "wav" {
            try wavData.write(to: url)
            return
        }

        // For other formats, use AVAssetWriter
        let tempWavURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try wavData.write(to: tempWavURL)
        defer { try? FileManager.default.removeItem(at: tempWavURL) }

        let asset = AVAsset(url: tempWavURL)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ConversionError.conversionFailed("No audio track in WAV file")
        }

        // Create writer
        let writer = try AVAssetWriter(outputURL: url, fileType: format == "m4a" ? .m4a : .wav)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 24000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000
        ]

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writer.add(writerInput)

        // Create reader
        let reader = try AVAssetReader(asset: asset)
        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 24000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerOutputSettings)
        reader.add(readerOutput)

        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.export")) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }

        await writer.finishWriting()

        if writer.status == .failed {
            throw ConversionError.exportFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
    }
}

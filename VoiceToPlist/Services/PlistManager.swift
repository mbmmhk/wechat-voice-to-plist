//
//  PlistManager.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/1.
//

import Foundation

/// Manages reading and writing plist files containing audio entries
class PlistManager {

    enum PlistError: LocalizedError {
        case invalidFormat
        case readFailed(Error)
        case writeFailed(Error)
        case invalidBase64

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Invalid plist format. Expected dictionary with string keys and base64 string values."
            case .readFailed(let error):
                return "Failed to read plist: \(error.localizedDescription)"
            case .writeFailed(let error):
                return "Failed to write plist: \(error.localizedDescription)"
            case .invalidBase64:
                return "Invalid base64 encoded data in plist."
            }
        }
    }

    /// Load audio entries from a plist file
    /// - Parameter url: URL of the plist file
    /// - Returns: Array of AudioEntry objects
    static func loadPlist(from url: URL) throws -> [AudioEntry] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PlistError.readFailed(error)
        }

        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw PlistError.readFailed(error)
        }

        guard let dict = plist as? [String: String] else {
            throw PlistError.invalidFormat
        }

        var entries: [AudioEntry] = []
        for (name, base64String) in dict {
            guard let silkData = Data(base64Encoded: base64String) else {
                throw PlistError.invalidBase64
            }
            entries.append(AudioEntry(name: name, silkData: silkData))
        }

        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Save audio entries to a plist file
    /// - Parameters:
    ///   - entries: Array of AudioEntry objects
    ///   - url: URL to save the plist file
    static func savePlist(entries: [AudioEntry], to url: URL) throws {
        var dict: [String: String] = [:]
        for entry in entries {
            dict[entry.name] = entry.silkData.base64EncodedString()
        }

        let data: Data
        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: dict,
                format: .xml,
                options: 0
            )
        } catch {
            throw PlistError.writeFailed(error)
        }

        do {
            try data.write(to: url)
        } catch {
            throw PlistError.writeFailed(error)
        }
    }

    /// Create a new empty plist file
    /// - Parameter url: URL to create the plist file
    static func createEmptyPlist(at url: URL) throws {
        try savePlist(entries: [], to: url)
    }
}

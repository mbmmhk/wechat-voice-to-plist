//
//  RVCService.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/2.
//

import Foundation

/// RVC Voice Conversion API Service
class RVCService {
    static let shared = RVCService()

    private let baseURL = "https://u176028-bdd3-3ab3ba4e.westb.seetacloud.com:8443"

    // MARK: - Models

    struct HealthResponse: Codable {
        let status: String
        let message: String
        let models_count: Int
    }

    struct VoiceModel: Codable, Identifiable, Hashable {
        let name: String
        let path: String
        let size_mb: Double
        let has_index: Bool
        let index_path: String?

        var id: String { name }
    }

    struct ConvertOptions {
        var pitch: Int = 0
        var f0Method: String = "rmvpe"
        var indexRate: Float = 0.5
        var filterRadius: Int = 3
        var rmsMixRate: Float = 0.25
        var protect: Float = 0.33
    }

    enum RVCError: LocalizedError {
        case serverUnavailable
        case invalidResponse
        case conversionFailed(String)
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .serverUnavailable:
                return "服务器不可用"
            case .invalidResponse:
                return "无效的服务器响应"
            case .conversionFailed(let message):
                return "转换失败: \(message)"
            case .networkError(let message):
                return "网络错误: \(message)"
            }
        }
    }

    // MARK: - API Methods

    /// Health check
    func checkHealth() async throws -> HealthResponse {
        let url = URL(string: "\(baseURL)/health")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RVCError.serverUnavailable
        }

        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    /// Check if server is available
    func isServerAvailable() async -> Bool {
        do {
            let health = try await checkHealth()
            return health.status == "ok"
        } catch {
            return false
        }
    }

    /// Fetch available models
    func fetchModels() async throws -> [VoiceModel] {
        let url = URL(string: "\(baseURL)/models")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RVCError.serverUnavailable
        }

        return try JSONDecoder().decode([VoiceModel].self, from: data)
    }

    /// Convert audio using specified model
    func convert(
        audioData: Data,
        filename: String,
        modelName: String,
        options: ConvertOptions = ConvertOptions()
    ) async throws -> Data {
        let url = URL(string: "\(baseURL)/convert")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120 // 2 minutes timeout for conversion

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Audio file
        body.appendMultipartFile(name: "audio", filename: filename, data: audioData, boundary: boundary)

        // Parameters
        body.appendMultipartField(name: "model_name", value: modelName, boundary: boundary)
        body.appendMultipartField(name: "pitch", value: "\(options.pitch)", boundary: boundary)
        body.appendMultipartField(name: "f0_method", value: options.f0Method, boundary: boundary)
        body.appendMultipartField(name: "index_rate", value: "\(options.indexRate)", boundary: boundary)
        body.appendMultipartField(name: "filter_radius", value: "\(options.filterRadius)", boundary: boundary)
        body.appendMultipartField(name: "rms_mix_rate", value: "\(options.rmsMixRate)", boundary: boundary)
        body.appendMultipartField(name: "protect", value: "\(options.protect)", boundary: boundary)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RVCError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw RVCError.conversionFailed(errorMsg)
        }

        return data
    }
}

// MARK: - Data Extension for Multipart

extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(name: String, filename: String, data: Data, boundary: String, mimeType: String = "audio/mpeg") {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}

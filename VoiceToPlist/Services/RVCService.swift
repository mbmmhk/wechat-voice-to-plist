//
//  RVCService.swift
//  VoiceToPlist
//
//  Created by Junjie Gu on 2026/1/2.
//

import Foundation

// MARK: - Server Configuration

struct RVCServer: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let isPreset: Bool

    init(id: String = UUID().uuidString, name: String, url: String, isPreset: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.isPreset = isPreset
    }

    static let presetServers: [RVCServer] = [
        RVCServer(id: "preset-1", name: "西北B区 / 170机", url: "https://u176028-bdd3-3ab3ba4e.westb.seetacloud.com:8443", isPreset: true),
        RVCServer(id: "preset-2", name: "西北B区 / 218机", url: "https://u176028-aac6-f575a1bd.westb.seetacloud.com:8443", isPreset: true),
        RVCServer(id: "preset-3", name: "西北B区 / 132机", url: "https://u176028-b628-c1844b7e.westb.seetacloud.com:8443", isPreset: true),
        RVCServer(id: "preset-4", name: "西北B区 / 161机", url: "https://u176028-9dad-96eba730.westb.seetacloud.com:8443", isPreset: true)
    ]
}

class RVCServerManager: ObservableObject {
    static let shared = RVCServerManager()

    @Published var selectedServer: RVCServer
    @Published var customServers: [RVCServer]

    private let selectedServerKey = "selectedServerID"
    private let customServersKey = "customServers"

    var allServers: [RVCServer] {
        RVCServer.presetServers + customServers
    }

    init() {
        // Load custom servers first
        var loadedCustomServers: [RVCServer] = []
        if let data = UserDefaults.standard.data(forKey: customServersKey),
           let servers = try? JSONDecoder().decode([RVCServer].self, from: data) {
            loadedCustomServers = servers
        }
        self.customServers = loadedCustomServers

        // Load selected server
        let selectedID = UserDefaults.standard.string(forKey: selectedServerKey) ?? RVCServer.presetServers.first!.id
        let allAvailableServers = RVCServer.presetServers + loadedCustomServers
        if let server = allAvailableServers.first(where: { $0.id == selectedID }) {
            self.selectedServer = server
        } else {
            self.selectedServer = RVCServer.presetServers.first!
        }
    }

    func selectServer(_ server: RVCServer) {
        selectedServer = server
        UserDefaults.standard.set(server.id, forKey: selectedServerKey)
    }

    func addCustomServer(name: String, url: String) -> RVCServer {
        let server = RVCServer(name: name, url: url, isPreset: false)
        customServers.append(server)
        saveCustomServers()
        return server
    }

    func removeCustomServer(_ server: RVCServer) {
        customServers.removeAll { $0.id == server.id }
        saveCustomServers()

        // If removed server was selected, switch to first preset
        if selectedServer.id == server.id {
            selectServer(RVCServer.presetServers.first!)
        }
    }

    func updateCustomServer(_ server: RVCServer, name: String, url: String) {
        if let index = customServers.firstIndex(where: { $0.id == server.id }) {
            let updated = RVCServer(id: server.id, name: name, url: url, isPreset: false)
            customServers[index] = updated
            saveCustomServers()

            if selectedServer.id == server.id {
                selectedServer = updated
            }
        }
    }

    private func saveCustomServers() {
        if let data = try? JSONEncoder().encode(customServers) {
            UserDefaults.standard.set(data, forKey: customServersKey)
        }
    }
}

/// RVC Voice Conversion API Service
class RVCService {
    static let shared = RVCService()

    private var baseURL: String {
        RVCServerManager.shared.selectedServer.url
    }

    // MARK: - Models

    struct HealthResponse: Codable {
        let status: String
        let message: String
        let models_count: Int
    }

    struct VoiceModel: Codable, Identifiable, Hashable {
        let name: String              // 文件名（不含后缀）
        let display_name: String      // 显示名称（中文名）
        let path: String              // 文件路径
        let size_mb: Double           // 文件大小
        let has_index: Bool           // 是否有索引
        let index_path: String?       // 索引路径
        let version: String?          // 模型版本 (v1/v2)
        let sample_rate: String?      // 采样率标签 (40k/48k)
        let actual_sr: Int?           // 实际采样率 (40000/48000)
        let has_pitch: Bool?          // 是否有音高
        let info: String?             // 模型描述
        let blend_group: String?      // 融合兼容组（相同组可融合）

        var id: String { name }

        // 便捷属性：格式化的版本和采样率信息（使用实际采样率）
        var versionInfo: String {
            var parts: [String] = []
            if let v = version {
                parts.append(v)
            }
            // 优先使用实际采样率
            if let sr = actual_sr {
                parts.append("\(sr / 1000)k")
            } else if let sr = sample_rate {
                parts.append(sr)
            }
            return parts.joined(separator: " / ")
        }

        // 检查是否可以与另一个模型融合
        func canBlendWith(_ other: VoiceModel) -> Bool {
            guard let myGroup = blend_group, let otherGroup = other.blend_group else {
                return false
            }
            return myGroup == otherGroup && name != other.name
        }
    }

    struct ConvertOptions {
        var pitch: Int = 0
        var f0Method: String = "rmvpe"
        var indexRate: Float = 0.5
        var filterRadius: Int = 3
        var rmsMixRate: Float = 0.25
        var protect: Float = 0.33
    }

    struct BlendModel: Codable {
        let name: String
        let weight: Float
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

    /// Convert audio using blended models (fusion)
    func convertBlend(
        audioData: Data,
        filename: String,
        model1Name: String,
        model2Name: String,
        blendRatio: Float,  // 0.0 = 100% model2, 1.0 = 100% model1
        options: ConvertOptions = ConvertOptions()
    ) async throws -> Data {
        let url = URL(string: "\(baseURL)/convert_blend")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180 // 3 minutes timeout for blend conversion

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Audio file
        body.appendMultipartFile(name: "audio", filename: filename, data: audioData, boundary: boundary)

        // Models JSON
        let models = [
            BlendModel(name: model1Name, weight: blendRatio),
            BlendModel(name: model2Name, weight: 1.0 - blendRatio)
        ]
        let modelsJSON = try JSONEncoder().encode(models)
        let modelsString = String(data: modelsJSON, encoding: .utf8)!
        body.appendMultipartField(name: "models_json", value: modelsString, boundary: boundary)

        // Parameters
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

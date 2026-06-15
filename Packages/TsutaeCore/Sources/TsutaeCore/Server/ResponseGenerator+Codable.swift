import Foundation
import Hummingbird
import NIOCore

/// 让所有 Codable 类型都能作为 ResponseGenerator
/// 自动编码为 JSON 响应
extension ResponseGenerator where Self: Codable {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(self)
        
        var response = Response(status: .ok)
        response.headers[.contentType] = "application/json"
        response.body = .init(byteBuffer: ByteBuffer(data: data))
        return response
    }
}

// 让我们的模型类型符合 ResponseGenerator
extension Config: ResponseGenerator {}
extension Recipe: ResponseGenerator {}
extension HotkeysConfig: ResponseGenerator {}
extension HealthStatus: ResponseGenerator {}
extension StateResponse: ResponseGenerator {}
extension ModelsResponse: ResponseGenerator {}
extension TTSNotifyResponse: ResponseGenerator {}
extension SecretsListResponse: ResponseGenerator {}
extension ErrorResponse: ResponseGenerator {}

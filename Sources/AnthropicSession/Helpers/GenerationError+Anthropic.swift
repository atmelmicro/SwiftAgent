// By Dennis Müller

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftAgent

public extension GenerationError {
  /// Anthropic-specific HTTP error mapping with optional payload decoding.
  static func from(_ httpError: HTTPError) -> GenerationError {
    fromHTTP(httpError, override: anthropicHTTPOverride)
  }
}

private extension GenerationError {
  struct AnthropicErrorEnvelope: Decodable {
    struct ErrorDetail: Decodable {
      let type: String
      let message: String
    }

    let type: String
    let error: ErrorDetail
  }

  static func anthropicHTTPOverride(_ httpError: HTTPError) -> GenerationError? {
    guard case let .unacceptableStatus(statusCode, data) = httpError else {
      return nil
    }

    if statusCode == 408 {
      return nil
    }

    guard let apiError = decodeAPIError(from: data) else {
      return nil
    }

    let message = bestMessage(for: statusCode, apiError: apiError)
    return .providerError(
      ProviderErrorContext(
        message: message,
        statusCode: statusCode,
        type: apiError.error.type,
      ),
    )
  }

  static func decodeAPIError(from data: Data?) -> AnthropicErrorEnvelope? {
    guard let data else {
      return nil
    }

    let decoder = JSONDecoder()
    do {
      return try decoder.decode(AnthropicErrorEnvelope.self, from: data)
    } catch {
      return nil
    }
  }

  static func bestMessage(for statusCode: Int, apiError: AnthropicErrorEnvelope) -> String {
    let message = apiError.error.message.trimmingCharacters(in: .whitespacesAndNewlines)
    if !message.isEmpty {
      return message
    }

    let defaultMessage = HTTPURLResponse.localizedString(forStatusCode: statusCode)
    let trimmed = defaultMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "HTTP status \(statusCode)" : trimmed
  }
}

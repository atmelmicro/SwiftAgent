// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct SessionSchema {}

@Suite("Anthropic - HTTP Error Mapping")
struct AnthropicHTTPErrorMappingTests {
  @Test("401 responses are mapped to providerError with statusCode + type")
  func authenticationErrorMapping() async throws {
    let mockHTTPClient = ReplayHTTPClient<AnthropicMessageRequest>(
      recordedResponse: .init(body: authenticationErrorResponse, statusCode: 401),
    )
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    let session = AnthropicSession(
      schema: SessionSchema(),
      instructions: "",
      configuration: configuration,
    )

    do {
      _ = try await session.respond(
        to: "prompt",
        using: .other("claude-haiku-4-5"),
      )
      Issue.record("Expected respond to throw")
    } catch {
      guard let generationError = error as? GenerationError else {
        Issue.record("Expected GenerationError but received \(error)")
        return
      }

      switch generationError {
      case let .providerError(context):
        #expect(context.statusCode == 401)
        #expect(context.type == "authentication_error")
        #expect(context.code == nil)
        #expect(context.message == "Invalid API key")
      default:
        Issue.record("Expected GenerationError.providerError but received \(generationError)")
      }
    }
  }

  @Test("429 responses are mapped to providerError with statusCode + type")
  func rateLimitErrorMapping() async throws {
    let mockHTTPClient = ReplayHTTPClient<AnthropicMessageRequest>(
      recordedResponse: .init(body: rateLimitErrorResponse, statusCode: 429),
    )
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    let session = AnthropicSession(
      schema: SessionSchema(),
      instructions: "",
      configuration: configuration,
    )

    do {
      _ = try await session.respond(
        to: "prompt",
        using: .other("claude-haiku-4-5"),
      )
      Issue.record("Expected respond to throw")
    } catch {
      guard let generationError = error as? GenerationError else {
        Issue.record("Expected GenerationError but received \(error)")
        return
      }

      switch generationError {
      case let .providerError(context):
        #expect(context.statusCode == 429)
        #expect(context.type == "rate_limit_error")
        #expect(context.code == nil)
        #expect(context.message == "Too many requests")
      default:
        Issue.record("Expected GenerationError.providerError but received \(generationError)")
      }
    }
  }
}

// MARK: - Fixtures

private let authenticationErrorResponse: String = #"""
{
  "type": "error",
  "error": {
    "type": "authentication_error",
    "message": "Invalid API key"
  }
}
"""#

private let rateLimitErrorResponse: String = #"""
{
  "type": "error",
  "error": {
    "type": "rate_limit_error",
    "message": "Too many requests"
  }
}
"""#

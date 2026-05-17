// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@Suite("Anthropic - Generation Options Validation")
struct AnthropicGenerationOptionsValidationTests {
  private let session: AnthropicSession<NoSchema>
  private let mockHTTPClient: ReplayHTTPClient<AnthropicMessageRequest>

  init() async {
    mockHTTPClient = ReplayHTTPClient<AnthropicMessageRequest>(recordedResponses: [])
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(schema: NoSchema(), instructions: "", configuration: configuration)
  }

  @Test("Missing maxOutputTokens throws before sending a request")
  func missingMaxOutputTokensThrows() async {
    do {
      _ = try await session.respond(
        to: "Hello",
        using: .other("claude-haiku-4-5"),
        options: AnthropicGenerationOptions(),
      )
      Issue.record("Expected AnthropicGenerationOptionsError.missingMaxTokens")
    } catch AnthropicGenerationOptionsError.missingMaxTokens {
      // Expected
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.isEmpty)
  }

  @Test("Thinking budget must be at least 1024")
  func thinkingBudgetTooLowThrows() async {
    let options = AnthropicGenerationOptions(
      maxOutputTokens: 64,
      thinking: .init(budgetTokens: 16),
    )

    do {
      _ = try await session.respond(
        to: "Hello",
        using: .other("claude-haiku-4-5"),
        options: options,
      )
      Issue.record("Expected AnthropicGenerationOptionsError.invalidThinkingBudget")
    } catch let AnthropicGenerationOptionsError.invalidThinkingBudget(value) {
      #expect(value == 16)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.isEmpty)
  }

  @Test("maxOutputTokens must be greater than thinking budget")
  func maxOutputTokensMustExceedThinkingBudget() async {
    let options = AnthropicGenerationOptions(
      maxOutputTokens: 1024,
      thinking: .init(budgetTokens: 1024),
    )

    do {
      _ = try await session.respond(
        to: "Hello",
        using: .other("claude-haiku-4-5"),
        options: options,
      )
      Issue.record("Expected AnthropicGenerationOptionsError.thinkingBudgetExceedsMaxOutputTokens")
    } catch let AnthropicGenerationOptionsError.thinkingBudgetExceedsMaxOutputTokens(
      budgetTokens,
      maxOutputTokens,
    ) {
      #expect(budgetTokens == 1024)
      #expect(maxOutputTokens == 1024)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.isEmpty)
  }

  @Test("Thinking disabled is sent as disabled without enabled-thinking validation")
  func thinkingDisabledIsSent() async throws {
    let httpClient = ReplayHTTPClient<AnthropicMessageRequest>(
      recordedResponse: .init(body: textResponse),
      makeJSONDecoder: {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
      },
    )
    let session = AnthropicSession(
      schema: NoSchema(),
      instructions: "",
      configuration: AnthropicConfiguration(httpClient: httpClient),
    )
    let options = AnthropicGenerationOptions(
      maxOutputTokens: 64,
      temperature: 0.7,
      thinking: .disabled,
    )

    _ = try await session.respond(
      to: "Hello",
      using: AnthropicModel.other("claude-haiku-4-5"),
      options: options,
    )

    let recordedRequests = await httpClient.recordedRequests()
    #expect(recordedRequests.count == 1)

    let request = recordedRequests[0].body
    let json = try requestJSON(from: request)
    let thinking = json["thinking"] as? [String: Any]
    let thinkingType = thinking?["type"] as? String
    #expect(thinkingType == "disabled")
    #expect(thinking?["budget_tokens"] == nil)
    #expect(json["temperature"] as? Double == 0.7)
  }

  private func requestJSON(
    from request: AnthropicMessageRequest,
  ) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let data = try encoder.encode(request)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let json = object as? [String: Any] else {
      throw GenerationError.requestFailed(
        reason: .decodingFailure,
        detail: "Failed to decode request JSON",
      )
    }

    return json
  }
}

private let textResponse: String = #"""
{
  "content" : [
    {
      "text" : "Hello from Claude",
      "type" : "text"
    }
  ],
  "id" : "msg_test",
  "model" : "claude-haiku-4-5",
  "role" : "assistant",
  "stop_reason" : "end_turn",
  "stop_sequence" : null,
  "type" : "message",
  "usage" : {
    "cache_creation_input_tokens" : 0,
    "cache_read_input_tokens" : 0,
    "input_tokens" : 10,
    "output_tokens" : 5
  }
}
"""#

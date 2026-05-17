// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct SessionSchema {
  @StructuredOutput(WeatherReport.self) var weatherReport
}

@Suite("Anthropic - Structured Output")
struct AnthropicStructuredOutputTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: AnthropicSession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<AnthropicMessageRequest>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<AnthropicMessageRequest>(
      recordedResponse: .init(body: structuredOutputResponse),
      makeJSONDecoder: {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
      },
    )
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(
      schema: SessionSchema(),
      instructions: "",
      configuration: configuration,
    )
  }

  @Test("Structured response is decoded into WeatherReport")
  func structuredResponseIsDecoded() async throws {
    let agentResponse = try await session.respond(
      to: "Weather update",
      generating: WeatherReport.self,
      using: .other("claude-haiku-4-5"),
    )

    try await validateHTTPRequests()
    validateAgentResponse(agentResponse)
  }

  // MARK: - Private Test Helper Methods

  private func validateHTTPRequests() async throws {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 1)

    let request = recordedRequests[0]
    let json = try requestJSON(from: request.body)

    guard let toolChoice = json["tool_choice"] as? [String: Any] else {
      Issue.record("Expected tool_choice in request JSON")
      return
    }

    #expect(toolChoice["type"] as? String == "tool")
    #expect(toolChoice["name"] as? String == "swiftagent_structured_output")
    #expect(toolChoice["disable_parallel_tool_use"] as? Bool == true)

    guard let tools = json["tools"] as? [[String: Any]],
          let firstTool = tools.first else {
      Issue.record("Expected tools in request JSON")
      return
    }

    #expect(firstTool["name"] as? String == "swiftagent_structured_output")
  }

  private func validateAgentResponse(
    _ agentResponse: AgentResponse<WeatherReport>,
  ) {
    #expect(agentResponse.content.temperature == 21)
    #expect(agentResponse.content.condition == "Sunny")

    let generatedTranscript = agentResponse.transcript
    #expect(generatedTranscript.count == 2)

    guard case let .prompt(promptEntry) = generatedTranscript[0] else {
      Issue.record("Expected first transcript entry to be .prompt")
      return
    }

    #expect(promptEntry.input == "Weather update")

    guard case let .response(responseEntry) = generatedTranscript[1] else {
      Issue.record("Expected second transcript entry to be .response")
      return
    }

    #expect(responseEntry.segments.count == 1)
    guard case let .structure(structuredSegment) = responseEntry.segments.first else {
      Issue.record("Expected response segment to be .structure")
      return
    }

    #expect(structuredSegment.typeName == WeatherReport.name)
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

private struct WeatherReport: StructuredOutput {
  static let name: String = "weather_report"

  @Generable
  struct Schema {
    var temperature: Int
    var condition: String
  }
}

// MARK: - Mock Responses

private let structuredOutputResponse: String = #"""
{
  "content" : [
    {
      "id" : "toolu_01PXo4ESZKeM5etz63HFfeqw",
      "input" : {
        "condition" : "Sunny",
        "temperature" : 21
      },
      "name" : "swiftagent_structured_output",
      "type" : "tool_use"
    }
  ],
  "id" : "msg_01RPrztWTKhWuXMb8SoR2pWV",
  "model" : "claude-haiku-4-5-20251001",
  "role" : "assistant",
  "stop_reason" : "tool_use",
  "stop_sequence" : null,
  "type" : "message",
  "usage" : {
    "cache_creation" : {
      "ephemeral_1h_input_tokens" : 0,
      "ephemeral_5m_input_tokens" : 0
    },
    "cache_creation_input_tokens" : 0,
    "cache_read_input_tokens" : 0,
    "input_tokens" : 695,
    "output_tokens" : 42,
    "service_tier" : "standard"
  }
}
"""#

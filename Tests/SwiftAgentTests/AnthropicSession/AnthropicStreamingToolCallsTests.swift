// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct SessionSchema {
  @Tool var weather = WeatherTool()
}

@Suite("Anthropic - Streaming - Tool Calls")
struct AnthropicStreamingToolCallsTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: AnthropicSession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<AnthropicMessageRequest>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<AnthropicMessageRequest>(
      recordedResponses: [
        .init(body: toolCallResponse),
        .init(body: finalResponse),
      ],
    )
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(schema: SessionSchema(), instructions: "", configuration: configuration)
  }

  @Test("Streaming tool call merges input JSON deltas")
  func streamingToolCallMergesInput() async throws {
    let generatedTranscript = try await processStreamResponse()

    await validateHTTPRequests()
    try validateTranscript(generatedTranscript: generatedTranscript)
  }

  // MARK: - Private Test Helper Methods

  private func processStreamResponse() async throws -> Transcript {
    let stream = try session.streamResponse(
      to: "Weather update",
      using: .other("claude-haiku-4-5"),
    )

    var generatedTranscript = Transcript()

    for try await snapshot in stream {
      generatedTranscript = snapshot.transcript
    }

    return generatedTranscript
  }

  private func validateHTTPRequests() async {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 2)
  }

  private func validateTranscript(generatedTranscript: Transcript) throws {
    guard let toolCalls = firstToolCalls(in: generatedTranscript) else {
      Issue.record("Expected tool call entry")
      return
    }

    #expect(toolCalls.calls.count == 1)
    #expect(toolCalls.calls[0].toolName == "get_weather")

    let expectedArguments = try GeneratedContent(
      json: #"{ "location": "Tokyo", "requestedDate": "2026-01-15", "timeOfDay": "afternoon" }"#,
    )
    #expect(toolCalls.calls[0].arguments.stableJsonString == expectedArguments.stableJsonString)

    guard let toolOutput = firstToolOutput(in: generatedTranscript) else {
      Issue.record("Expected tool output entry")
      return
    }
    guard case let .structure(structuredSegment) = toolOutput.segment else {
      Issue.record("Expected tool output to be structured")
      return
    }

    #expect(structuredSegment.content.generatedContent.kind == .string("Sunny"))

    guard let responseText = lastResponseText(in: generatedTranscript) else {
      Issue.record("Expected response text")
      return
    }

    #expect(responseText == "Done.")
  }

  private func firstToolCalls(
    in transcript: Transcript,
  ) -> Transcript.ToolCalls? {
    for entry in transcript {
      guard case let .toolCalls(toolCalls) = entry else {
        continue
      }

      return toolCalls
    }

    return nil
  }

  private func firstToolOutput(
    in transcript: Transcript,
  ) -> Transcript.ToolOutput? {
    for entry in transcript {
      guard case let .toolOutput(toolOutput) = entry else {
        continue
      }

      return toolOutput
    }

    return nil
  }

  private func lastResponseText(
    in transcript: Transcript,
  ) -> String? {
    var responseText: String?
    for entry in transcript {
      guard case let .response(response) = entry else {
        continue
      }

      responseText = response.text
    }

    return responseText
  }
}

// MARK: - Tool

private struct WeatherTool: FoundationModels.Tool {
  var name: String = "get_weather"
  var description: String = "Get current weather for a given location."

  @Generable
  struct Arguments {
    var location: String
    var requestedDate: String
    var timeOfDay: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}

// MARK: - Mock Responses

private let toolCallResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_01MarALNmiF8csykns86dUzm","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":657,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":25,"service_tier":"standard"}}               }

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_015n4uw36Cgq6shEyjPGjH5k","name":"get_weather","input":{}}              }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":""}   }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"lo"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"ca"}           }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"tion\": \"T"}  }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"okyo\""}         }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":", \"reque"}  }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"stedD"}   }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"ate\": \"2026"}        }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"-0"}               }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"1-1"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"5\""}            }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":", \"tim"}              }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"eOfDay\": \"af"}           }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"tern"}         }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"oon\"}"}              }

event: content_block_stop
data: {"type":"content_block_stop","index":0   }

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":657,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":97}}

event: message_stop
data: {"type":"message_stop"   }
"""#

private let finalResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_01C1J9D3xP6vVLz5tPh2TRyo","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":769,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":1,"service_tier":"standard"}} }

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}       }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Done"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"."}             }

event: content_block_stop
data: {"type":"content_block_stop","index":0             }

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":769,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}    }

event: message_stop
data: {"type":"message_stop"            }
"""#

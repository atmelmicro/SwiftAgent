// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct NoArgsSessionSchema {
  @Tool var ping = PingTool()
}

@Suite("Anthropic - Streaming - Tool Calls (No Args)")
struct AnthropicStreamingToolCallsNoArgsTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: AnthropicSession<NoArgsSessionSchema>
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
    session = AnthropicSession(schema: NoArgsSessionSchema(), instructions: "", configuration: configuration)
  }

  @Test("Executes tool call with empty arguments")
  func executesToolCallWithEmptyArguments() async throws {
    let generatedTranscript = try await processStreamResponse()

    await validateHTTPRequests()
    try validateTranscript(generatedTranscript: generatedTranscript)
  }

  // MARK: - Private Test Helper Methods

  private func processStreamResponse() async throws -> Transcript {
    let stream = try session.streamResponse(
      to: "Ping",
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
    #expect(toolCalls.calls[0].toolName == "ping")

    let expectedArguments = try GeneratedContent(json: #"{}"#)
    #expect(toolCalls.calls[0].arguments.stableJsonString == expectedArguments.stableJsonString)

    guard let toolOutput = firstToolOutput(in: generatedTranscript) else {
      Issue.record("Expected tool output entry")
      return
    }
    guard case let .structure(structuredSegment) = toolOutput.segment else {
      Issue.record("Expected tool output to be structured")
      return
    }

    #expect(structuredSegment.content.generatedContent.kind == .string("pong"))
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
}

// MARK: - Tool

private struct PingTool: FoundationModels.Tool {
  var name: String = "ping"
  var description: String = "Returns pong with no arguments."

  @Generable
  struct Arguments {
    init() {}
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "pong"
  }
}

// MARK: - Mock Responses

private let toolCallResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_01PbnX3z4TLRSaXRd7RrS3BS","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":581,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":25,"service_tier":"standard"}}   }

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_01EbB2HjbAqV1Hjjv2qoj9Lk","name":"ping","input":{}}        }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":""}       }

event: content_block_stop
data: {"type":"content_block_stop","index":0      }

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":581,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":35}}

event: message_stop
data: {"type":"message_stop"      }
"""#

private let finalResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_01WoQWJTVomzbE8ZAJozRWDC","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":631,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":1,"service_tier":"standard"}}    }

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}               }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"p"}            }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ong"}      }

event: content_block_stop
data: {"type":"content_block_stop","index":0   }

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":631,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}             }

event: message_stop
data: {"type":"message_stop"           }
"""#

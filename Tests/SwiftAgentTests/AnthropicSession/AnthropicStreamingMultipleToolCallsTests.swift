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
  @Tool var time = TimeTool()
}

@Suite("Anthropic - Streaming - Tool Calls (Multiple)")
struct AnthropicStreamingMultipleToolCallsTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: AnthropicSession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<AnthropicMessageRequest>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<AnthropicMessageRequest>(
      recordedResponses: [
        .init(body: multiToolUseResponse),
        .init(body: finalResponse),
      ],
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

  @Test("Multiple tool_use blocks interleave with text blocks and all tool outputs are recorded")
  func multipleToolUseBlocksAndTextBlocks() async throws {
    let (generatedTranscript, latestContent) = try await processStreamResponse()

    #expect(latestContent == "Done.")
    try validateTranscript(generatedTranscript)
  }

  // MARK: - Private

  private func processStreamResponse() async throws -> (Transcript, String?) {
    let stream = try session.streamResponse(
      to: "prompt",
      using: .other("claude-haiku-4-5"),
    )

    var generatedTranscript = Transcript()
    var latestContent: String?

    for try await snapshot in stream {
      generatedTranscript = snapshot.transcript
      if let content = snapshot.content {
        latestContent = content
      }
    }

    return (generatedTranscript, latestContent)
  }

  private func validateTranscript(
    _ transcript: Transcript,
  ) throws {
    #expect(transcript.count == 7)

    guard case let .prompt(promptEntry) = transcript[0] else {
      Issue.record("Expected first transcript entry to be .prompt")
      return
    }

    #expect(promptEntry.input == "prompt")

    guard case let .response(firstResponse) = transcript[1] else {
      Issue.record("Expected second transcript entry to be .response")
      return
    }

    #expect(firstResponse.textSegments.map(\.content) == [
      "Before tool calls.",
      "Between tool calls.",
      "After tool calls.",
    ])

    guard case let .toolCalls(weatherCalls) = transcript[2] else {
      Issue.record("Expected third transcript entry to be .toolCalls")
      return
    }

    #expect(weatherCalls.calls.count == 1)
    #expect(weatherCalls.calls[0].toolName == "get_weather")

    guard case let .toolCalls(timeCalls) = transcript[3] else {
      Issue.record("Expected fourth transcript entry to be .toolCalls")
      return
    }

    #expect(timeCalls.calls.count == 1)
    #expect(timeCalls.calls[0].toolName == "get_time")

    guard case let .toolOutput(weatherOutput) = transcript[4] else {
      Issue.record("Expected fifth transcript entry to be .toolOutput")
      return
    }

    #expect(weatherOutput.toolName == "get_weather")
    guard case let .structure(weatherSegment) = weatherOutput.segment else {
      Issue.record("Expected weather tool output segment to be .structure")
      return
    }

    #expect(weatherSegment.content.generatedContent.kind == .string("Sunny"))

    guard case let .toolOutput(timeOutput) = transcript[5] else {
      Issue.record("Expected sixth transcript entry to be .toolOutput")
      return
    }

    #expect(timeOutput.toolName == "get_time")
    guard case let .structure(timeSegment) = timeOutput.segment else {
      Issue.record("Expected time tool output segment to be .structure")
      return
    }

    #expect(timeSegment.content.generatedContent.kind == .string("12:34"))

    guard case let .response(finalResponse) = transcript[6] else {
      Issue.record("Expected seventh transcript entry to be .response")
      return
    }

    #expect(finalResponse.text == "Done.")
  }
}

// MARK: - Tools

private struct WeatherTool: FoundationModels.Tool {
  var name: String = "get_weather"
  var description: String = "Get current weather for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "Sunny"
  }
}

private struct TimeTool: FoundationModels.Tool {
  var name: String = "get_time"
  var description: String = "Get current local time for a given location."

  @Generable
  struct Arguments {
    var location: String
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments
    return "12:34"
  }
}

// MARK: - Fixtures

private let multiToolUseResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_multi_tool_use","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":1,"service_tier":"standard"}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Before tool calls."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_weather","name":"get_weather","input":{"location":"Tokyo"}}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: content_block_start
data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":"Between tool calls."}}

event: content_block_stop
data: {"type":"content_block_stop","index":2}

event: content_block_start
data: {"type":"content_block_start","index":3,"content_block":{"type":"tool_use","id":"toolu_time","name":"get_time","input":{"location":"Tokyo"}}}

event: content_block_stop
data: {"type":"content_block_stop","index":3}

event: content_block_start
data: {"type":"content_block_start","index":4,"content_block":{"type":"text","text":"After tool calls."}}

event: content_block_stop
data: {"type":"content_block_stop","index":4}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}

event: message_stop
data: {"type":"message_stop"}
"""#

private let finalResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_multi_tool_use_final","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":1,"service_tier":"standard"}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Done."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":3}}

event: message_stop
data: {"type":"message_stop"}
"""#

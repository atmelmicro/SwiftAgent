// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct SessionSchema {}

@Suite("Anthropic - Streaming - Text")
struct AnthropicStreamingTextTests {
  typealias Transcript = SwiftAgent.Transcript

  // MARK: - Properties

  private let session: AnthropicSession<SessionSchema>
  private let mockHTTPClient: ReplayHTTPClient<AnthropicMessageRequest>

  // MARK: - Initialization

  init() async {
    mockHTTPClient = ReplayHTTPClient<AnthropicMessageRequest>(
      recordedResponse: .init(body: streamingResponse),
    )
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(schema: SessionSchema(), instructions: "", configuration: configuration)
  }

  @Test("Single streamed response")
  func singleResponse() async throws {
    let (generatedTranscript, latestContent) = try await processStreamResponse()

    await validateHTTPRequests()
    try validateTranscript(generatedTranscript: generatedTranscript)
    #expect(latestContent == "Hello")
  }

  // MARK: - Private Test Helper Methods

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

  private func validateHTTPRequests() async {
    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 1)

    let request = recordedRequests[0]
    let json = try? requestJSON(from: request.body)

    #expect(json?["stream"] as? Bool == true)
    #expect(json?["model"] as? String == AnthropicModel.other("claude-haiku-4-5").rawValue)
  }

  private func validateTranscript(generatedTranscript: Transcript) throws {
    #expect(generatedTranscript.count == 2)

    guard case let .prompt(prompt) = generatedTranscript[0] else {
      Issue.record("First transcript entry is not .prompt")
      return
    }

    #expect(prompt.input == "prompt")

    guard case let .response(response) = generatedTranscript[1] else {
      Issue.record("Second transcript entry is not .response")
      return
    }

    #expect(response.segments.count == 1)
    guard case let .text(textSegment) = response.segments.first else {
      Issue.record("Second transcript entry is not .text")
      return
    }

    #expect(textSegment.content == "Hello")
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

// MARK: - Mock Responses

private let streamingResponse: String = #"""
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_01JzuY8iEcEAEmz3udfvgitz","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":13,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":1,"service_tier":"standard"}} }

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}              }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0            }

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":13,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":4}            }

event: message_stop
data: {"type":"message_stop"     }
"""#

// By Dennis Müller

@testable import AnthropicSession
import Foundation
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@Suite("Anthropic - Streaming - Thinking")
struct AnthropicStreamingThinkingRoundtripTests {
  private let session: AnthropicSession<NoSchema>
  private let mockHTTPClient: ReplayHTTPClient<AnthropicMessageRequest>

  init() async {
    mockHTTPClient = ReplayHTTPClient<AnthropicMessageRequest>(
      recordedResponses: [
        .init(body: response1),
        .init(body: response2),
      ],
      makeJSONDecoder: {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
      },
    )
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(schema: NoSchema(), instructions: "", configuration: configuration)
  }

  @Test("Thinking blocks from the first turn are forwarded on the next request")
  func thinkingBlocksAreForwardedOnNextRequest() async throws {
    let options = AnthropicGenerationOptions(
      maxOutputTokens: 2048,
      thinking: .init(budgetTokens: 1024),
      minimumStreamingSnapshotInterval: .zero,
    )

    let stream = try session.streamResponse(
      to: "First prompt",
      using: .other("claude-haiku-4-5"),
      options: options,
    )
    for try await _ in stream {}

    _ = try await session.respond(
      to: "Second prompt",
      using: .other("claude-haiku-4-5"),
      options: options,
    )

    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.count == 2)

    let secondRequest = recordedRequests[1].body
    let assistantRole = MessageParameter.Message.Role.assistant.rawValue
    guard let assistantMessage = secondRequest.messages.first(where: { $0.role == assistantRole }) else {
      Issue.record("Expected an assistant message in the second request")
      return
    }
    guard case let .list(objects) = assistantMessage.content else {
      Issue.record("Expected assistant message content to be a list")
      return
    }

    let containsThinking = objects.contains { object in
      if case .thinking = object {
        return true
      }
      return false
    }
    #expect(containsThinking)
  }
}

// MARK: - Recorded Responses

/// POST https://api.anthropic.com/v1/messages (stream)
private let response1: String = #"""
event: message_start
data: {"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"msg_01JGV8rjtVNNewg8jSLnRWfx","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":44,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"output_tokens":8,"service_tier":"standard"}}    }

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""} }

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"The user has given me a first prompt"}  }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" that"}    }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" says"}               }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" \"First prompt\" an"}  }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"d then"}             }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" asks me to reply with exactly: Hello"}    }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"\n\nSo"} }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" I should reply"}            }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" with exactly"}      }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" \"Hello\""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}           }

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EroCCkYICxgCKkBV7ym+AuCJRVQIYTqlw70w9Kx3BqkgKZZsQbloOV07dZxDk3ofuwjMYP3cYYcI+sss0DD2HCQyc5F8eDYTnitPEgyjhQ2Di0Grwrd29OEaDPvPlfuPE7k+02504iIwked6+j9NVWReYYgOAbe+X0eeijrHa//TIw0SqE+VpRpIErK3Xd8iz4LK01HKe2xBKqEBSzQ3qH8HqQDUGgQA8ySC1hSqqWrX7V+oFmKnbiV66pb8dPyVRuhPIbxX9giDhg0IJJrG/4LEGPPZOLZ8C9sAv7Htvo+P9BrFHsVjR5Toxxj9L5AcwAtndte1i0GMapplz+Q28qClNlhLzq4mCBAmTtlxHLJHoCUBVbLGlDUGqSsFAAAbvsdJxaJXr1DmbxbgbttjnmDYj0J1SFngleU4HqsYAQ=="}          }

event: content_block_stop
data: {"type":"content_block_stop","index":0              }

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}              }

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}    }

event: content_block_stop
data: {"type":"content_block_stop","index":1          }

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":44,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":46}           }

event: message_stop
data: {"type":"message_stop"          }
"""#

/// POST https://api.anthropic.com/v1/messages
private let response2: String = #"""
{
  "content" : [
    {
      "signature" : "EoEGCkYICxgCKkCgj1wIzXUa036l8rG1P20hgBrSJZIC\\/fE19fWRPtlycPxMINJBNTvvqNcQKFxIDAYbXc\\/WE+m791ob4iHHJifUEgx3Wh2TS9X2sNburl0aDGWOCaxrtrlMvTzf7iIwAy7LOu9+FytqZnRFDmB855zUcwoPuv4LivICBHZBuCZcBTVWWMK9GErXq7os2fnUKugEFLiGjju8vwCIwjpSanW+VEU3AInIH589Gwce1eLfkzcXksqB6waocsIgD9rqBMHM9ENg9jLJ8Cx3k+2U13JNYqsYR+aSe7J8aH3kQZotnEb2JWXIC6ZtD7y8XgdYGnwcdhoXONrV1crzarg4NbyN1aA66Z4BsWcS6F4e7yxPBTUQfAtHMYNY8AuJC5o6M6bpPUSKeSq0Y4Kk+LsE\\/u6mJ4ijgWQz6\\/yCjMC+QnTGkXmkomuLsJC3xT061oh0Er+SNq96mTA4XHUVibPqTAoQYYn6ok4uz97qp+PKzulD4i6ymCwB+JYlcCrnjgRfn1pOGRybENulI9oowZb5z7NCa6wHiIfImQ6xftINToo+L3r9mGyvurSpdRfFA9H22cBfBfv2T7KgulrjH+rt0e3JHR8pm6XFOpHZgjDYbnnv37wN2Z\\/ROlkDgKniel1EtRj0IbNp361LdSzuVY+drKma+Z1Vthhk81EP2J+Ey8bl14vXp4Y5DRyw\\/+09SEp9qM9FrV0\\/Jc8ZI3DqGKG\\/PU0e6TFVF7+6633sCPc675I1cfG6pbXr+jaGwFOLLZqqTYr4fu4i3KSU8XxItazrnxY\\/MykKlrMh\\/v2TxG3TNtObA45t3UBeouFr9foagEOAnzG+1fUh7O454CYPMTpthHyAFAmGJk1gifOG\\/viJVJ4pR7WsAo9+aLUhet3B7nwjIQOga3lzWK4xla\\/jX\\/4L4uQb+fBH0+YYM0FHik\\/I2Vt\\/kzP3pKbhUxpRHF3cHVU29z\\/19CaeC6gUgw9XJwRNf2kVQzO3xrIN\\/GDavwNCoUt3l54YONPAu8kHGBgB",
      "thinking" : "The user's second prompt just says \"Second prompt\". Looking back at the instructions, I was told \"Reply with exactly: Hello\". \\n\\nThe instruction says to reply with exactly \"Hello\" - but it's not clear if this applies to every response or just the first one. However, the instruction was given at the very beginning and seems to be a standing instruction for how I should respond.\\n\\nLet me reconsider - the instruction says \"Reply with exactly: Hello\" which is a pretty clear directive. It doesn't say \"for the first prompt only\" or have any conditional. So I should follow it for this response as well.",
      "type" : "thinking"
    },
    {
      "text" : "Hello",
      "type" : "text"
    }
  ],
  "id" : "msg_018vpWvgUYmZVeVfjSUBhNmN",
  "model" : "claude-haiku-4-5-20251001",
  "role" : "assistant",
  "stop_reason" : "end_turn",
  "stop_sequence" : null,
  "type" : "message",
  "usage" : {
    "cache_creation" : {
      "ephemeral_1h_input_tokens" : 0,
      "ephemeral_5m_input_tokens" : 0
    },
    "cache_creation_input_tokens" : 0,
    "cache_read_input_tokens" : 0,
    "input_tokens" : 53,
    "output_tokens" : 143,
    "service_tier" : "standard"
  }
}
"""#

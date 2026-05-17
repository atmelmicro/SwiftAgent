// By Dennis Müller

@testable import AnthropicSession
import FoundationModels
@testable import SwiftAgent
import SwiftAnthropic
import Testing

@SessionSchema
private struct SchemaWithStructuredOutput {
  @StructuredOutput(WeatherReport.self) var weatherReport
}

@Suite("Anthropic - Thinking - Compatibility Validation")
struct AnthropicThinkingCompatibilityValidationTests {
  private let session: AnthropicSession<NoSchema>
  private let mockHTTPClient: ReplayHTTPClient<AnthropicMessageRequest>

  private let structuredSession: AnthropicSession<SchemaWithStructuredOutput>
  private let structuredHTTPClient: ReplayHTTPClient<AnthropicMessageRequest>

  init() async {
    mockHTTPClient = ReplayHTTPClient<AnthropicMessageRequest>(recordedResponses: [])
    let configuration = AnthropicConfiguration(httpClient: mockHTTPClient)
    session = AnthropicSession(schema: NoSchema(), instructions: "", configuration: configuration)

    structuredHTTPClient = ReplayHTTPClient<AnthropicMessageRequest>(recordedResponses: [])
    let structuredConfiguration = AnthropicConfiguration(httpClient: structuredHTTPClient)
    structuredSession = AnthropicSession(
      schema: SchemaWithStructuredOutput(),
      instructions: "",
      configuration: structuredConfiguration,
    )
  }

  @Test("Thinking + temperature is rejected before sending a request")
  func thinkingWithTemperatureIsRejected() async {
    let options = AnthropicGenerationOptions(
      maxOutputTokens: 2048,
      temperature: 0.7,
      thinking: .init(budgetTokens: 1024),
    )

    do {
      _ = try await session.respond(
        to: "Hello",
        using: .other("claude-haiku-4-5"),
        options: options,
      )
      Issue.record("Expected AnthropicGenerationOptionsError.thinkingIncompatibleWithTemperature")
    } catch AnthropicGenerationOptionsError.thinkingIncompatibleWithTemperature {
      // Expected
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.isEmpty)
  }

  @Test("Thinking + toolChoice(any) is rejected before sending a request")
  func thinkingWithForcedToolChoiceIsRejected() async {
    let options = AnthropicGenerationOptions(
      maxOutputTokens: 2048,
      toolChoice: .init(type: .any),
      thinking: .init(budgetTokens: 1024),
    )

    do {
      _ = try await session.respond(
        to: "Hello",
        using: .other("claude-haiku-4-5"),
        options: options,
      )
      Issue.record("Expected AnthropicGenerationOptionsError.thinkingIncompatibleWithToolChoice")
    } catch let AnthropicGenerationOptionsError.thinkingIncompatibleWithToolChoice(type) {
      #expect(type == "any")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let recordedRequests = await mockHTTPClient.recordedRequests()
    #expect(recordedRequests.isEmpty)
  }

  @Test("Thinking + structured output is rejected before sending a request")
  func thinkingWithStructuredOutputIsRejected() async {
    let options = AnthropicGenerationOptions(
      maxOutputTokens: 2048,
      thinking: .init(budgetTokens: 1024),
    )

    do {
      _ = try await structuredSession.respond(
        to: "Hello",
        generating: WeatherReport.self,
        using: .other("claude-haiku-4-5"),
        options: options,
      )
      Issue.record("Expected AnthropicGenerationOptionsError.thinkingIncompatibleWithStructuredOutput")
    } catch AnthropicGenerationOptionsError.thinkingIncompatibleWithStructuredOutput {
      // Expected
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let recordedRequests = await structuredHTTPClient.recordedRequests()
    #expect(recordedRequests.isEmpty)
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

// By Dennis Müller

import Foundation
import FoundationModels
import Observation
import SwiftAgent

/// High-level client for working with Anthropic's Messages API using SwiftAgent.
///
/// `AnthropicSession` pairs an ``AnthropicAdapter`` with your tools or schema so you can request
/// completions, stream updates, and inspect transcripts without wiring adapters by hand. Supply a
/// ``SessionSchema`` when you need typed transcripts, or pass tools directly for quick prototypes.
@Observable
public final class AnthropicSession<
  SessionSchema: LanguageModelSessionSchema,
>: LanguageModelProvider, @unchecked Sendable {
  public typealias Adapter = AnthropicAdapter

  /// Adapter that performs network requests against Anthropic's Messages API.
  @ObservationIgnored public let adapter: AnthropicAdapter

  @ObservationIgnored public var schema: SessionSchema

  /// Registered tools available to the model during a session.
  @ObservationIgnored public var tools: [any SwiftAgentTool] {
    adapter.tools
  }

  /// Transcript of the session, including prompts, tool calls, and model outputs.
  public var transcript: SwiftAgent.Transcript = Transcript()

  /// Aggregated token accounting reported by Anthropic for the active session.
  public var tokenUsage: TokenUsage = .init()

  /// Creates a session that exposes the provided tools without defining a schema.
  ///
  /// - Parameters:
  ///   - tools: Variadic list of tools available to the model.
  ///   - instructions: Default instructions applied to every turn.
  ///   - apiKey: Anthropic API key used for direct authentication.
  ///   - baseURL: Base URL for Anthropic's Messages API.
  ///   - apiVersion: Anthropic API version header value.
  ///   - betaHeaders: Optional beta header flags for Anthropic.
  public init<each ToolType>(
    tools: repeat each ToolType,
    instructions: String = "",
    apiKey: String,
    baseURL: URL = URL(string: "https://api.anthropic.com")!,
    apiVersion: String = "2023-06-01",
    betaHeaders: [String]? = nil,
  ) where
    SessionSchema == NoSchema,
    repeat (each ToolType): FoundationModels.Tool,
    repeat (each ToolType).Arguments: Generable,
    repeat (each ToolType).Output: Generable {
    var wrappedTools: [any SwiftAgentTool] = []
    _ = (repeat wrappedTools.append(_SwiftAgentToolWrapper(tool: each tools)))

    schema = NoSchema()
    adapter = AnthropicAdapter(
      tools: wrappedTools,
      instructions: instructions,
      configuration: .direct(
        apiKey: apiKey,
        baseURL: baseURL,
        apiVersion: apiVersion,
        betaHeaders: betaHeaders,
      ),
    )
  }

  /// Creates a schema-backed session using a direct API key.
  ///
  /// - Parameters:
  ///   - schema: The schema that enumerates tools, structured outputs, and groundings.
  ///   - instructions: Default instructions applied to every turn.
  ///   - apiKey: Anthropic API key used for direct authentication.
  ///   - baseURL: Base URL for Anthropic's Messages API.
  ///   - apiVersion: Anthropic API version header value.
  ///   - betaHeaders: Optional beta header flags for Anthropic.
  public init(
    schema: SessionSchema,
    instructions: String,
    apiKey: String,
    baseURL: URL = URL(string: "https://api.anthropic.com")!,
    apiVersion: String = "2023-06-01",
    betaHeaders: [String]? = nil,
  ) {
    self.schema = schema
    adapter = AnthropicAdapter(
      tools: schema.tools,
      instructions: instructions,
      configuration: .direct(
        apiKey: apiKey,
        baseURL: baseURL,
        apiVersion: apiVersion,
        betaHeaders: betaHeaders,
      ),
    )
  }

  /// Creates a schema-backed session with a custom configuration (for proxies or advanced options).
  ///
  /// - Parameters:
  ///   - schema: The schema that enumerates tools, structured outputs, and groundings.
  ///   - instructions: Default instructions applied to every turn.
  ///   - configuration: Anthropic configuration describing routing and authentication.
  public init(
    schema: SessionSchema,
    instructions: String,
    configuration: AnthropicConfiguration,
  ) {
    self.schema = schema
    adapter = AnthropicAdapter(
      tools: schema.tools,
      instructions: instructions,
      configuration: configuration,
    )
  }

  /// Creates a tool-only session backed by a custom configuration.
  ///
  /// - Parameters:
  ///   - tools: Variadic list of tools available to the model.
  ///   - instructions: Default instructions applied to every turn.
  ///   - configuration: Anthropic configuration describing routing and authentication.
  public init<each ToolType>(
    tools: repeat each ToolType,
    instructions: String = "",
    configuration: AnthropicConfiguration,
  ) where SessionSchema == NoSchema,
    repeat (each ToolType): FoundationModels.Tool,
    repeat (each ToolType).Arguments: Generable,
    repeat (each ToolType).Output: Generable {
    var wrappedTools: [any SwiftAgentTool] = []
    _ = (repeat wrappedTools.append(_SwiftAgentToolWrapper(tool: each tools)))

    schema = NoSchema()
    adapter = AnthropicAdapter(
      tools: wrappedTools,
      instructions: instructions,
      configuration: configuration,
    )
  }
}

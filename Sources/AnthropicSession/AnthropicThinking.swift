// By Dennis Müller

import Foundation

/// Anthropic extended thinking configuration.
public struct AnthropicThinking: Encodable, Equatable, Sendable {
  /// Whether Anthropic extended thinking should be enabled or disabled.
  public var type: ThinkingType

  /// Token budget allocated for enabled extended thinking.
  public var budgetTokens: Int?

  public enum ThinkingType: String, Encodable, Equatable, Sendable {
    case enabled
    case disabled
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case budgetTokens = "budget_tokens"
  }

  /// Creates an Anthropic thinking configuration.
  ///
  /// Use ``disabled`` to explicitly send `{"type":"disabled"}`.
  public init(type: ThinkingType, budgetTokens: Int? = nil) {
    self.type = type
    self.budgetTokens = budgetTokens
  }

  /// Enables Anthropic extended thinking with a fixed token budget.
  public init(budgetTokens: Int) {
    self.init(type: .enabled, budgetTokens: budgetTokens)
  }

  /// Explicitly disables Anthropic thinking for the request.
  public static let disabled = AnthropicThinking(type: .disabled)
}

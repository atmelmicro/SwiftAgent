// By Dennis Müller

import Foundation
import SwiftAgent
@preconcurrency import SwiftAnthropic

extension AnthropicAdapter {
  func messageRequest(
    including transcript: Transcript,
    generating type: (some StructuredOutput).Type?,
    using model: Model,
    options: AnthropicGenerationOptions,
    streamResponses: Bool,
  ) throws -> AnthropicMessageRequest {
    guard let maxTokens = options.maxOutputTokens else {
      throw AnthropicGenerationOptionsError.missingMaxTokens
    }

    if options.thinking?.type == .enabled, type != nil {
      throw AnthropicGenerationOptionsError.thinkingIncompatibleWithStructuredOutput
    }

    let messages = try AnthropicMessageBuilder.messages(
      from: transcript,
      includeThinking: options.thinking?.type == .enabled,
    )

    let systemPrompt: MessageParameter.System? = instructions.isEmpty
      ? nil
      : .text(instructions)

    let toolChoice = try resolvedToolChoice(
      for: type,
      options: options,
    )

    let tools = try resolvedTools(
      for: type,
    )

    let base = MessageParameter(
      model: .other(model.rawValue),
      messages: messages,
      maxTokens: maxTokens,
      system: systemPrompt,
      metadata: nil,
      stopSequences: options.stopSequences,
      stream: streamResponses,
      temperature: options.temperature,
      topK: options.topK,
      topP: options.topP,
      tools: tools,
      toolChoice: toolChoice,
      thinking: nil,
      container: nil,
    )

    return AnthropicMessageRequest(
      base: base,
      thinking: options.thinking,
    )
  }

  func structuredOutputToolName(
    for typeName: String?,
  ) throws -> String? {
    guard typeName != nil else {
      return nil
    }

    let baseName = "swiftagent_structured_output"

    if tools.contains(where: { $0.name == baseName }) {
      throw GenerationError.requestFailed(
        reason: .invalidRequestConfiguration,
        detail: "Tool name conflict with reserved tool \"\(baseName)\".",
      )
    }

    return baseName
  }
}

private extension AnthropicAdapter {
  func resolvedToolChoice(
    for type: (some StructuredOutput).Type?,
    options: AnthropicGenerationOptions,
  ) throws -> MessageParameter.ToolChoice? {
    if let type {
      guard let name = try structuredOutputToolName(for: type.name) else {
        throw GenerationError.requestFailed(
          reason: .invalidRequestConfiguration,
          detail: "Structured output requires a tool name.",
        )
      }

      return MessageParameter.ToolChoice(
        type: .tool,
        name: name,
        disableParallelToolUse: true,
      )
    }

    return options.toolChoice
  }

  func resolvedTools(
    for type: (some StructuredOutput).Type?,
  ) throws -> [MessageParameter.Tool]? {
    var resolved: [MessageParameter.Tool] = try tools.map { tool in
      try .function(
        name: tool.name,
        description: tool.description,
        inputSchema: tool.parameters.asAnthropicJSONSchema(),
        cacheControl: nil,
      )
    }

    if let type {
      guard let name = try structuredOutputToolName(for: type.name) else {
        throw GenerationError.requestFailed(
          reason: .invalidRequestConfiguration,
          detail: "Structured output requires a tool name.",
        )
      }

      let schema = type.Schema.generationSchema
      let jsonSchema = try schema.asAnthropicJSONSchema()

      resolved.append(
        .function(
          name: name,
          description: "SwiftAgent structured output: \(type.name)",
          inputSchema: jsonSchema,
          cacheControl: nil,
        ),
      )
    }

    return resolved.isEmpty ? nil : resolved
  }
}

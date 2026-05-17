// By Dennis Müller

import Foundation
import FoundationModels
import SwiftAgent
@preconcurrency import SwiftAnthropic

extension AnthropicAdapter {
  public func streamResponse(
    to prompt: Transcript.Prompt,
    generating type: (some StructuredOutput).Type?,
    using model: Model = .default,
    including transcript: Transcript,
    options: AnthropicGenerationOptions,
  ) -> AsyncThrowingStream<AdapterUpdate, any Error> {
    let setup = AsyncThrowingStream<AdapterUpdate, any Error>.makeStream()

    AgentLog.start(
      model: String(describing: model),
      toolNames: tools.map(\.name),
      promptPreview: prompt.input,
    )

    let task = Task<Void, Never> {
      do {
        try options.validate(for: model)
      } catch {
        AgentLog.error(error, context: "Invalid generation options")
        setup.continuation.finish(throwing: error)
        return
      }

      do {
        try await runStreamResponse(
          transcript: transcript,
          generating: type,
          using: model,
          options: options,
          continuation: setup.continuation,
        )

        AgentLog.finish()
        setup.continuation.finish()
      } catch {
        AgentLog.error(error, context: "streaming response")
        setup.continuation.finish(throwing: error)
        return
      }

      setup.continuation.finish()
    }

    setup.continuation.onTermination = { _ in
      task.cancel()
    }

    return setup.stream
  }

  private func runStreamResponse(
    transcript: Transcript,
    generating type: (some StructuredOutput).Type?,
    using model: Model,
    options: AnthropicGenerationOptions,
    continuation: AsyncThrowingStream<AdapterUpdate, any Error>.Continuation,
  ) async throws {
    var generatedTranscript = Transcript()
    var entryIndices: [String: Int] = [:]
    var messageState: StreamingMessageState?
    var reasoningState: StreamingReasoningState?
    var toolCallStates: [String: StreamingToolCallState] = [:]
    var toolCallOrder: [String] = []
    var toolUseIdsByIndex: [Int: String] = [:]

    let structuredOutputTypeName = type?.name
    let structuredToolName = try structuredOutputToolName(for: structuredOutputTypeName)

    let allowedSteps = 20
    var currentStep = 0

    stepLoop: for _ in 0..<allowedSteps {
      try Task.checkCancellation()
      currentStep += 1
      AgentLog.stepRequest(step: currentStep)

      let accumulatedTranscript = Transcript(entries: transcript.entries + generatedTranscript.entries)
      let request = try messageRequest(
        including: accumulatedTranscript,
        generating: type,
        using: model,
        options: options,
        streamResponses: true,
      )

      let eventStream = httpClient.stream(
        path: messagesPath,
        method: .post,
        headers: [:],
        body: request,
      )

      let decoder = AnthropicMessageStreamEventDecoder()
      var responseCompleted = false
      var shouldContinueLoop = false

      do {
        streamLoop: for try await event in eventStream {
          try Task.checkCancellation()
          guard let decoded = try decoder.decodeEvent(from: event) else {
            continue
          }

          if let error = decoded.payload.error {
            throw GenerationError.providerError(
              message: error.message,
              code: nil,
              type: error.type,
              parameter: nil,
            )
          }

          if let usage = decoded.payload.usage,
             let tokenUsage = tokenUsage(from: usage) {
            continuation.yield(.tokenUsage(tokenUsage))
          }

          switch decoded.type {
          case MessageStreamResponse.StreamEvent.messageStart.rawValue:
            try handleMessageStart(
              decoded.payload,
              includeThinking: options.thinking?.type == .enabled,
              structuredOutputTypeName: structuredOutputTypeName,
              structuredToolName: structuredToolName,
              messageState: &messageState,
              reasoningState: &reasoningState,
              generatedTranscript: &generatedTranscript,
              entryIndices: &entryIndices,
              continuation: continuation,
            )

          case MessageStreamResponse.StreamEvent.contentBlockStart.rawValue:
            try handleContentBlockStart(
              decoded.payload,
              structuredToolName: structuredToolName,
              messageState: &messageState,
              reasoningState: &reasoningState,
              toolCallStates: &toolCallStates,
              toolCallOrder: &toolCallOrder,
              toolUseIdsByIndex: &toolUseIdsByIndex,
              generatedTranscript: &generatedTranscript,
              entryIndices: &entryIndices,
              continuation: continuation,
            )

          case MessageStreamResponse.StreamEvent.contentBlockDelta.rawValue:
            try handleContentBlockDelta(
              decoded.payload,
              messageState: &messageState,
              reasoningState: &reasoningState,
              toolCallStates: &toolCallStates,
              toolUseIdsByIndex: toolUseIdsByIndex,
              generatedTranscript: &generatedTranscript,
              entryIndices: &entryIndices,
              continuation: continuation,
            )

          case MessageStreamResponse.StreamEvent.contentBlockStop.rawValue:
            try handleContentBlockStop(
              decoded.payload,
              messageState: &messageState,
              toolCallStates: &toolCallStates,
              toolUseIdsByIndex: toolUseIdsByIndex,
              generatedTranscript: &generatedTranscript,
              entryIndices: &entryIndices,
              continuation: continuation,
            )

          case MessageStreamResponse.StreamEvent.messageDelta.rawValue:
            handleMessageDelta(
              decoded.payload,
              messageState: &messageState,
              generatedTranscript: &generatedTranscript,
              continuation: continuation,
            )

          case MessageStreamResponse.StreamEvent.messageStop.rawValue:
            responseCompleted = true
            try finalizeMessage(
              messageState: &messageState,
              reasoningState: &reasoningState,
              generatedTranscript: &generatedTranscript,
              entryIndices: &entryIndices,
              continuation: continuation,
            )
            break streamLoop

          default:
            continue
          }
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw GenerationError.fromStream(error, httpErrorMapper: GenerationError.from)
      }

      try Task.checkCancellation()

      guard responseCompleted else {
        continue stepLoop
      }

      if !toolCallOrder.isEmpty {
        let didExecuteAny = try await executeQueuedToolCalls(
          inOrder: toolCallOrder,
          toolCallStates: &toolCallStates,
          generatedTranscript: &generatedTranscript,
          continuation: continuation,
        )

        if didExecuteAny {
          shouldContinueLoop = true
        }
      }

      if shouldContinueLoop {
        continue stepLoop
      }

      return
    }
  }
}

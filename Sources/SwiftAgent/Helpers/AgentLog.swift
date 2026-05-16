// By Dennis Müller

import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Centralized, human-friendly logging for agent runs and tool calls.
///
/// Uses the SDK's `Logger.main` instance to emit concise, readable console output
/// with consistent formatting. JSON payloads are pretty-printed when possible.
package enum AgentLog {
  private static func log(_ level: String, _ message: String) {
    #if canImport(OSLog)
    switch level {
    case "debug":
      Logger.main.debug("\(message, privacy: .public)")
    case "warning":
      Logger.main.warning("\(message, privacy: .public)")
    case "error":
      Logger.main.error("\(message, privacy: .public)")
    default:
      Logger.main.info("\(message, privacy: .public)")
    }
    #else
    print(message)
    #endif
  }

  /// Logs the start of an agent run.
  package static func start(model: String, toolNames: [String], promptPreview: String?) {
    let tools = toolNames.isEmpty ? "-" : toolNames.joined(separator: ", ")
    let preview = promptPreview.map { "\($0.prefix(180))" } ?? "-"
    log("info", "🟢 Agent start — model=\(model) | tools=\(tools) | prompt=\(preview)")
  }

  /// Logs that the provider is requesting the next response step.
  package static func stepRequest(step: Int) {
    log("debug", "↗️ Request step #\(step)")
  }

  /// Logs a plain message output from the model.
  package static func outputMessage(text: String, status: String) {
    let preview = text.trimmingCharacters(in: .whitespacesAndNewlines)
    log("info", "💬 Output — status=\(status)\n\(preview)")
  }

  /// Logs a structured (JSON) output from the model.
  package static func outputStructured(json: String, status: String) {
    log("info", "📦 Structured output — status=\(status)\n\(pretty(json: json))")
  }

  /// Logs that a tool call was requested by the model.
  package static func toolCall(name: String, callId: String, argumentsJSON: String) {
    log("info", "🛠️ Tool call — \(name) [\(callId)]\nargs:\n\(pretty(json: argumentsJSON))")
  }

  /// Logs tool output after the tool completed successfully.
  package static func toolOutput(name: String, callId: String, outputJSONOrText: String) {
    let body = pretty(json: outputJSONOrText)
    log("info", "📤 Tool output — \(name) [\(callId)]\n\(body)")
  }

  /// Logs a reasoning summary if available.
  package static func reasoning(summary: [String]) {
    guard !summary.isEmpty else { return }

    let joined = summary.joined(separator: "\n• ")
    log("debug", "🧠 Reasoning\n• \(joined)")
  }

  /// Logs that the run finished.
  package static func finish() {
    log("info", "✅ Finished")
  }

  /// Logs token usage accounting.
  package static func tokenUsage(
    inputTokens: Int?,
    outputTokens: Int?,
    totalTokens: Int?,
    cachedTokens: Int?,
    reasoningTokens: Int?,
  ) {
    let input = inputTokens.map(String.init) ?? "-"
    let output = outputTokens.map(String.init) ?? "-"
    let total = totalTokens.map(String.init) ?? "-"
    let cached = cachedTokens.map(String.init) ?? "-"
    let reasoning = reasoningTokens.map(String.init) ?? "-"

    log("info", "🧮 Token usage — input=\(input) | output=\(output) | total=\(total) | cached=\(cached) | reasoning=\(reasoning)")
  }

  /// Logs an error during the run.
  package static func error(_ error: any Error, context: String? = nil) {
    let ctx = context ?? "-"
    let errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    log("error", "⛔️ Error — \(ctx): \(errorMessage)")
  }

  // MARK: - General Logging

  /// Logs a debug message with optional context.
  package static func debug(_ message: String, context: String? = nil) {
    let formatted = context.map { "🔍 \($0) — \(message)" } ?? "🔍 \(message)"
    log("debug", formatted)
  }

  /// Logs an informational message with optional context.
  package static func info(_ message: String, context: String? = nil) {
    let formatted = context.map { "ℹ️ \($0) — \(message)" } ?? "ℹ️ \(message)"
    log("info", formatted)
  }

  /// Logs a success message with optional context.
  package static func success(_ message: String, context: String? = nil) {
    let formatted = context.map { "✅ \($0) — \(message)" } ?? "✅ \(message)"
    log("info", formatted)
  }

  /// Logs a warning message with optional context.
  package static func warning(_ message: String, context: String? = nil) {
    let formatted = context.map { "⚠️ \($0) — \(message)" } ?? "⚠️ \(message)"
    log("warning", formatted)
  }

  /// Pretty-prints a JSON string if possible, otherwise returns the input.
  package static func pretty(json: String) -> String {
    guard let data = json.data(using: .utf8) else { return json }

    do {
      let object = try JSONSerialization.jsonObject(with: data)
      let pretty = try JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted],
      )
      return String(data: pretty, encoding: .utf8) ?? json
    } catch {
      return json
    }
  }
}

// By Dennis Müller

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(OSLog)
import OSLog
#endif

/// Network-specific logging for HTTP requests and responses.
///
/// Provides detailed, formatted output of raw network traffic including URLs,
/// headers, and request/response bodies with pretty-printed JSON when possible.
public enum NetworkLog {
  /// Enable/disable network logging
  public nonisolated(unsafe) static var isEnabled: Bool = false

  /// Internal logger for network requests
  #if canImport(OSLog)
  private static let logger = Logger(subsystem: "SwiftAgent", category: "Network")
  #endif

  /// Logs an outgoing HTTP request with all details.
  static func request(_ request: URLRequest) {
    guard isEnabled else { return }

    let method = request.httpMethod ?? "GET"
    let url = request.url?.absoluteString ?? "unknown"
    let headers = formatHeaders(request.allHTTPHeaderFields)
    let body = formatBody(request.httpBody)

    log(
      """
      🌐 HTTP Request
      ↗️ \(method) \(url)
      Headers:
      \(headers)
      Body:
      \(body)
      """,
    )
  }

  /// Logs an incoming HTTP response with all details.
  static func response(_ response: URLResponse, data: Data?) {
    guard isEnabled else { return }
    guard let httpResponse = response as? HTTPURLResponse else {
      log("🌐 HTTP Response: Invalid response type")
      return
    }

    let statusCode = httpResponse.statusCode
    let url = httpResponse.url?.absoluteString ?? "unknown"
    let headers = formatHeaders(httpResponse.allHeaderFields as? [String: String])
    let body = formatResponseBody(data)

    let statusEmoji = statusCode >= 200 && statusCode < 300 ? "✅" : "❌"

    log(
      """
      🌐 HTTP Response \(statusEmoji)
      ↙️ \(statusCode) \(url)
      Headers:
      \(headers)
      Body:
      \(body)
      """,
    )
  }

  // MARK: - Private Helpers

  private static func log(_ message: String) {
    #if canImport(OSLog)
    logger.info("\(message, privacy: .public)")
    #else
    print(message)
    #endif
  }

  private static func formatHeaders(_ headers: [String: String]?) -> String {
    guard let headers, !headers.isEmpty else {
      return "  (none)"
    }

    return headers
      .sorted { $0.key < $1.key }
      .map { "  \($0.key): \($0.value)" }
      .joined(separator: "\n")
  }

  private static func formatBody(_ data: Data?) -> String {
    guard let data, !data.isEmpty else {
      return "  (empty)"
    }

    // Try to pretty-print as JSON first
    if let jsonString = tryPrettyPrintJSON(data) {
      return jsonString.components(separatedBy: .newlines)
        .map { "  \($0)" }
        .joined(separator: "\n")
    }

    // Fall back to string representation
    if let string = String(data: data, encoding: .utf8) {
      return string.components(separatedBy: .newlines)
        .map { "  \($0)" }
        .joined(separator: "\n")
    }

    // Last resort: show byte count
    return "  (binary data, \(data.count) bytes)"
  }

  private static func formatResponseBody(_ data: Data?) -> String {
    formatBody(data)
  }

  private static func tryPrettyPrintJSON(_ data: Data) -> String? {
    do {
      let object = try JSONSerialization.jsonObject(with: data)
      let prettyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
      return String(data: prettyData, encoding: .utf8)
    } catch {
      return nil
    }
  }
}

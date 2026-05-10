// By Dennis Müller

import Foundation
import SwiftAgent

public struct AnthropicConfiguration: AdapterConfiguration {
  var httpClient: HTTPClient

  public init(httpClient: HTTPClient) {
    self.httpClient = httpClient
  }

  /// Convenience builder for calling Anthropic directly with an API key.
  ///
  /// This is intended for prototyping only. Shipping an API key inside an app binary is
  /// insecure and should be avoided in production. Prefer ``proxy(through:)`` with
  /// short-lived, backend-issued tokens that are scoped to a single agent turn.
  ///
  /// - Parameter baseURL: The base URL for Anthropic's Messages API.
  public static func direct(
    apiKey: String,
    baseURL: URL = URL(string: "https://api.anthropic.com")!,
    apiVersion: String = "2023-06-01",
    betaHeaders: [String]? = nil,
  ) -> AnthropicConfiguration {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    var defaultHeaders: [String: String] = [
      "anthropic-version": apiVersion,
    ]

    if let betaHeaders {
      defaultHeaders["anthropic-beta"] = betaHeaders.joined(separator: ",")
    }

    let interceptors = HTTPClientInterceptors(
      prepareRequest: { request in
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
      },
      onUnauthorized: { _, _, _ in
        false
      },
    )

    let configuration = HTTPClientConfiguration(
      baseURL: baseURL,
      defaultHeaders: defaultHeaders,
      timeout: 60,
      jsonEncoder: encoder,
      jsonDecoder: decoder,
      interceptors: interceptors,
    )

    return AnthropicConfiguration(httpClient: URLSessionHTTPClient(configuration: configuration))
  }

  /// Configures the adapter to send all requests through your own proxy backend.
  ///
  /// The proxy approach is the recommended, secure way to use the SDK in apps. Your backend
  /// issues a short-lived token (for example, for a single agent turn) and the app attaches it
  /// to requests. This way, api keys never ship in the app bundle and communication with the backend stays secure.
  ///
  /// This configuration reads the token from the internal task-local authorization context that
  /// you set via ``LanguageModelProvider/withAuthorization(token:refresh:perform:)``. If the proxy responds
  /// with `401 Unauthorized` and a refresh closure was provided to `withAuthorization`, the SDK will
  /// obtain a new token from that closure and retry the request once.
  ///
  /// - Parameter baseURL: The base `URL` of your proxy backend.
  /// - Returns: A configured `AnthropicConfiguration` instance.
  public static func proxy(
    through baseURL: URL,
    apiVersion: String = "2023-06-01",
    betaHeaders: [String]? = nil,
  ) -> AnthropicConfiguration {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    var defaultHeaders: [String: String] = [
      "anthropic-version": apiVersion,
    ]

    if let betaHeaders {
      defaultHeaders["anthropic-beta"] = betaHeaders.joined(separator: ",")
    }

    let interceptors = HTTPClientInterceptors(
      prepareRequest: { request in
        guard let context = AuthorizationContext.current else {
          preconditionFailure("AnthropicConfiguration.proxy(through:) requires an authorization context.")
        }

        await request.setValue("Bearer \(context.bearerToken)", forHTTPHeaderField: "Authorization")
      },
      onUnauthorized: { _, _, _ in
        guard let context = AuthorizationContext.current, let refreshToken = await context.refreshToken else {
          return false
        }
        guard let newToken = try? await refreshToken() else {
          return false
        }

        await context.setBearerToken(newToken)
        return true
      },
    )

    let configuration = HTTPClientConfiguration(
      baseURL: baseURL,
      defaultHeaders: defaultHeaders,
      timeout: 60,
      jsonEncoder: encoder,
      jsonDecoder: decoder,
      interceptors: interceptors,
    )

    return AnthropicConfiguration(httpClient: URLSessionHTTPClient(configuration: configuration))
  }
}

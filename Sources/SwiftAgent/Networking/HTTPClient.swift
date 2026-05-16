// By Dennis Müller

import EventSource
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Public API

public protocol HTTPClient: Sendable {
  /// Sends an HTTP request with an Encodable JSON body and decodes the JSON response.
  @discardableResult
  func send<ResponseBody: Decodable>(
    path: String,
    method: HTTPMethod,
    queryItems: [URLQueryItem]?,
    headers: [String: String]?,
    body: (some Encodable & Sendable)?,
    responseType: ResponseBody.Type,
  ) async throws -> ResponseBody

  /// Streams Server-Sent Events from an HTTP endpoint.
  func stream(
    path: String,
    method: HTTPMethod,
    headers: [String: String],
    body: (some Encodable & Sendable)?,
  ) -> AsyncThrowingStream<EventSource.Event, Error>
}

public extension HTTPClient {
  /// Convenience overload that defaults to `.post` and no additional headers.
  func stream(
    path: String,
    headers: [String: String] = [:],
    body: (some Encodable & Sendable)? = nil,
  ) -> AsyncThrowingStream<EventSource.Event, Error> {
    stream(path: path, method: .post, headers: headers, body: body)
  }
}

public enum HTTPMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case delete = "DELETE"
  case patch = "PATCH"
}

/// A snapshot of an outgoing HTTP request.
///
/// This is intended for logging and fixture recording. It contains the full URL,
/// headers, and raw body bytes as sent by the SDK.
///
/// - Important: This may include sensitive information (e.g. `Authorization` header).
///   Prefer redacting before printing or persisting.
public struct HTTPRequestSnapshot: Sendable {
  /// Unique identifier for correlating this request with responses.
  public var id: UUID
  /// Fully qualified request URL (base URL + path + query items).
  public var url: URL
  /// HTTP method (e.g. `POST`).
  public var method: String
  /// Request headers as sent by the SDK (including those injected by interceptors).
  public var headers: [String: String]
  /// Raw request body bytes. Typically JSON, but may be `nil`.
  public var body: Data?
  /// True if this request is a retry (e.g. after a 401 token refresh).
  public var isRetry: Bool

  public init(
    id: UUID,
    url: URL,
    method: String,
    headers: [String: String],
    body: Data?,
    isRetry: Bool,
  ) {
    self.id = id
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
    self.isRetry = isRetry
  }
}

/// A snapshot of an incoming HTTP response.
///
/// This is intended for logging and fixture recording. It contains the response
/// status code, headers, and raw response bytes.
public struct HTTPResponseSnapshot: Sendable {
  /// The identifier of the request that produced this response.
  public var requestID: UUID
  /// Response URL, as reported by `HTTPURLResponse`.
  public var url: URL
  /// HTTP status code.
  public var statusCode: Int
  /// Response headers, normalized to string key/value pairs.
  public var headers: [String: String]
  /// Raw response body bytes (if any). For non-streaming requests, this is the full body.
  public var body: Data?
  /// True if this response corresponds to a retry request.
  public var isRetry: Bool

  public init(
    requestID: UUID,
    url: URL,
    statusCode: Int,
    headers: [String: String],
    body: Data?,
    isRetry: Bool,
  ) {
    self.requestID = requestID
    self.url = url
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
    self.isRetry = isRetry
  }
}

/// A snapshot of a Server-Sent Events response as observed by the client.
///
/// This is emitted for streaming endpoints (SSE). The `body` is the **raw**
/// `text/event-stream` payload as received over the network, suitable for pasting
/// into tests that replay SSE.
///
/// If the consumer stops iterating the stream early (for example, after receiving a
/// provider-specific “completed” event), the snapshot may contain a partial payload.
///
/// - Important: Capturing this snapshot requires buffering the full stream in memory.
///   Prefer enabling it only during development/fixture recording.
public struct HTTPStreamResponseSnapshot: Sendable {
  /// The identifier of the request that produced this stream.
  public var requestID: UUID
  /// Response URL, as reported by `HTTPURLResponse`.
  public var url: URL
  /// HTTP status code.
  public var statusCode: Int
  /// Response headers, normalized to string key/value pairs.
  public var headers: [String: String]
  /// Raw `text/event-stream` body.
  public var body: String
  /// True if this stream corresponds to a retry request.
  public var isRetry: Bool

  public init(
    requestID: UUID,
    url: URL,
    statusCode: Int,
    headers: [String: String],
    body: String,
    isRetry: Bool,
  ) {
    self.requestID = requestID
    self.url = url
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
    self.isRetry = isRetry
  }
}

/// Interceptors to customize request/response handling.
///
/// Use this to:
/// - Inject authentication headers (``prepareRequest``)
/// - Retry once on `401 Unauthorized` (``onUnauthorized``)
/// - Record or log requests/responses (``onRequest``, ``onResponse``, ``onStreamResponse``)
public struct HTTPClientInterceptors: Sendable {
  /// Allows adding auth headers or other customizations before the request is sent.
  public var prepareRequest: (@Sendable (inout URLRequest) async throws -> Void)?
  /// Called on 401 responses. Return true to indicate the request should be retried once (e.g. after refreshing auth).
  public var onUnauthorized: (@Sendable (
    _ response: HTTPURLResponse,
    _ data: Data?,
    _ originalRequest: URLRequest,
  ) async -> Bool)?
  /// Called after a request is fully prepared (including auth headers).
  ///
  /// This is the last hook before the request is sent. Prefer doing lightweight work here.
  public var onRequest: (@Sendable (_ request: HTTPRequestSnapshot) async -> Void)?
  /// Called after a response is received (including non-2xx responses).
  ///
  /// For streaming requests, this is only called when the server returns a non-2xx status.
  /// On successful SSE streams, use ``onStreamResponse``.
  public var onResponse: (@Sendable (_ response: HTTPResponseSnapshot) async -> Void)?
  /// Called when a Server-Sent Events stream ends (finish or cancellation).
  ///
  /// The snapshot contains the raw `text/event-stream` payload captured up to that point.
  /// Enabling this hook makes the client buffer stream bytes in memory, which is useful for
  /// fixture recording but generally undesirable in production.
  public var onStreamResponse: (@Sendable (_ response: HTTPStreamResponseSnapshot) async -> Void)?

  public init(
    prepareRequest: (@Sendable (inout URLRequest) async throws -> Void)? = nil,
    onUnauthorized: (@Sendable (
      _ response: HTTPURLResponse,
      _ data: Data?,
      _ originalRequest: URLRequest,
    ) async -> Bool)? = nil,
    onRequest: (@Sendable (_ request: HTTPRequestSnapshot) async -> Void)? = nil,
    onResponse: (@Sendable (_ response: HTTPResponseSnapshot) async -> Void)? = nil,
    onStreamResponse: (@Sendable (_ response: HTTPStreamResponseSnapshot) async -> Void)? = nil,
  ) {
    self.prepareRequest = prepareRequest
    self.onUnauthorized = onUnauthorized
    self.onRequest = onRequest
    self.onResponse = onResponse
    self.onStreamResponse = onStreamResponse
  }
}

public struct HTTPClientConfiguration: Sendable {
  public var baseURL: URL
  public var defaultHeaders: [String: String]
  public var timeout: TimeInterval
  public var jsonEncoder: JSONEncoder
  public var jsonDecoder: JSONDecoder
  public var interceptors: HTTPClientInterceptors

  public init(
    baseURL: URL,
    defaultHeaders: [String: String] = [:],
    timeout: TimeInterval = 60,
    jsonEncoder: JSONEncoder = JSONEncoder(),
    jsonDecoder: JSONDecoder = JSONDecoder(),
    interceptors: HTTPClientInterceptors = .init(),
  ) {
    self.baseURL = baseURL
    self.defaultHeaders = defaultHeaders
    self.timeout = timeout
    self.jsonEncoder = jsonEncoder
    self.jsonDecoder = jsonDecoder
    self.interceptors = interceptors
  }
}

public enum HTTPError: Error, Sendable, LocalizedError {
  case invalidURL
  case requestFailed(underlying: Error)
  case invalidResponse
  case unacceptableStatus(code: Int, data: Data?)
  case decodingFailed(underlying: DecodingError, data: Data?)

  public var errorDescription: String? {
    switch self {
    case .invalidURL:
      "Invalid URL"
    case let .requestFailed(underlying):
      "Request failed: \(underlying.localizedDescription)"
    case .invalidResponse:
      "Invalid response"
    case let .unacceptableStatus(code, data):
      if let data, let msg = HTTPErrorMessageExtractor.extract(from: data) {
        "HTTP \(code): \(msg)"
      } else {
        "Unacceptable status code: \(code)"
      }
    case let .decodingFailed(underlying, data):
      if let data, let body = HTTPErrorMessageExtractor.string(from: data) {
        "Failed to decode response: \(underlying.localizedDescription). Body: \(body)"
      } else {
        "Failed to decode response: \(underlying.localizedDescription)"
      }
    }
  }
}

// MARK: - Implementation

public final class URLSessionHTTPClient: HTTPClient {
  let configuration: HTTPClientConfiguration
  let urlSession: URLSession

  public init(configuration: HTTPClientConfiguration, session: URLSession? = nil) {
    self.configuration = configuration

    if let session {
      urlSession = session
    } else {
      let config = URLSessionConfiguration.default
      config.timeoutIntervalForRequest = configuration.timeout
      config.timeoutIntervalForResource = configuration.timeout
      urlSession = URLSession(configuration: config)
    }
  }

  public func send<ResponseBody: Decodable>(
    path: String,
    method: HTTPMethod,
    queryItems: [URLQueryItem]?,
    headers: [String: String]?,
    body: (some Encodable & Sendable)?,
    responseType: ResponseBody.Type,
  ) async throws -> ResponseBody {
    let url = try makeURL(path: path, queryItems: queryItems)
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    // Apply default headers then custom headers
    for (key, value) in configuration.defaultHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }

    if let headers {
      for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
      }
    }

    if let body {
      request.httpBody = try configuration.jsonEncoder.encode(body)
    }

    // Allow caller to inject auth headers etc.
    if let prepare = configuration.interceptors.prepareRequest {
      do {
        try await prepare(&request)
      } catch {
        throw HTTPError.requestFailed(underlying: error)
      }
    }

    let requestID = UUID()
    await recordRequestSnapshotIfNeeded(
      requestID: requestID,
      request: request,
      isRetry: false,
    )

    // Log the outgoing request
    NetworkLog.request(request)

    // Perform request, with one optional retry on 401
    do {
      let (data, response) = try await perform(request: request)

      // Log the response
      NetworkLog.response(response, data: data)
      await recordResponseSnapshotIfNeeded(
        requestID: requestID,
        response: response,
        data: data,
        isRetry: false,
      )

      if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401,
         let onUnauthorized = configuration.interceptors.onUnauthorized {
        let shouldRetry = await onUnauthorized(httpResponse, data, request)
        if shouldRetry {
          var retryRequest = request
          // Allow re-preparing the request (e.g. with refreshed token)
          if let prepare = configuration.interceptors.prepareRequest {
            do {
              try await prepare(&retryRequest)
            } catch {
              throw HTTPError.requestFailed(underlying: error)
            }
          }

          let retryRequestID = UUID()
          await recordRequestSnapshotIfNeeded(
            requestID: retryRequestID,
            request: retryRequest,
            isRetry: true,
          )

          // Log the retry request
          NetworkLog.request(retryRequest)

          let (retryData, retryResponse) = try await perform(request: retryRequest)

          // Log the retry response
          NetworkLog.response(retryResponse, data: retryData)
          await recordResponseSnapshotIfNeeded(
            requestID: retryRequestID,
            response: retryResponse,
            data: retryData,
            isRetry: true,
          )

          return try decode(ResponseBody.self, data: retryData, response: retryResponse)
        }
      }

      return try decode(ResponseBody.self, data: data, response: response)
    } catch {
      throw error
    }
  }

  // MARK: - Helpers

  private func recordRequestSnapshotIfNeeded(
    requestID: UUID,
    request: URLRequest,
    isRetry: Bool,
  ) async {
    guard let hook = configuration.interceptors.onRequest else {
      return
    }
    guard let url = request.url else {
      return
    }

    let snapshot = HTTPRequestSnapshot(
      id: requestID,
      url: url,
      method: request.httpMethod ?? "GET",
      headers: request.allHTTPHeaderFields ?? [:],
      body: request.httpBody,
      isRetry: isRetry,
    )

    await hook(snapshot)
  }

  private func recordResponseSnapshotIfNeeded(
    requestID: UUID,
    response: URLResponse,
    data: Data?,
    isRetry: Bool,
  ) async {
    guard let hook = configuration.interceptors.onResponse else {
      return
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      return
    }
    guard let url = httpResponse.url else {
      return
    }

    let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
      let key = String(describing: pair.key)
      let value = String(describing: pair.value)
      partialResult[key] = value
    }

    let snapshot = HTTPResponseSnapshot(
      requestID: requestID,
      url: url,
      statusCode: httpResponse.statusCode,
      headers: headers,
      body: data,
      isRetry: isRetry,
    )

    await hook(snapshot)
  }

  func makeURL(path: String, queryItems: [URLQueryItem]?) throws -> URL {
    guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
      throw HTTPError.invalidURL
    }

    // Ensure single slash between base and path
    let trimmedBasePath = (components.path as NSString).standardizingPath
    let trimmedPath = ("/" + path).replacingOccurrences(of: "//", with: "/")
    components.path = (trimmedBasePath + "/" + trimmedPath).replacingOccurrences(of: "//", with: "/")
    components.queryItems = queryItems

    guard let url = components.url else { throw HTTPError.invalidURL }

    return url
  }

  private func perform(request: URLRequest) async throws -> (Data, URLResponse) {
    do {
      return try await urlSession.data(for: request)
    } catch {
      throw HTTPError.requestFailed(underlying: error)
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw HTTPError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw HTTPError.unacceptableStatus(code: httpResponse.statusCode, data: data)
    }

    do {
      return try configuration.jsonDecoder.decode(type, from: data)
    } catch let decodingError as DecodingError {
      throw HTTPError.decodingFailed(underlying: decodingError, data: data)
    } catch {
      throw error
    }
  }
}

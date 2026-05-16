// By Dennis Müller

import EventSource
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension URLSessionHTTPClient {
  // MARK: - Public API (provider-agnostic)

  /// Opens a Server-Sent Events stream and yields `SSEEvent` frames as they arrive.
  ///
  /// - Parameters:
  ///   - path: Relative API path (joined with the client's `baseURL`).
  ///   - method: HTTP method to use. Defaults to `.post` for response streaming APIs.
  ///   - headers: Additional headers. `Accept: text/event-stream` is set automatically.
  ///   - body: Optional JSON body (encoded with the client's JSON encoder).
  /// - Returns: `AsyncThrowingStream<SSEEvent, Error>`.
  func stream(
    path: String,
    method: HTTPMethod = .post,
    headers: [String: String] = [:],
    body: (some Encodable)? = nil,
  ) -> AsyncThrowingStream<EventSource.Event, Error> {
    let encodedBodyResult = Result<Data?, Error> {
      try body.map { try configuration.jsonEncoder.encode($0) }
    }

    // Use explicit unbounded buffering to avoid back‑pressure when callers
    // temporarily pause consumption (e.g. while awaiting tool execution).
    return AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
      let task = Task {
        do {
          let requestBody = try encodedBodyResult.get()
          let url = try makeURL(path: path, queryItems: nil)
          var request = URLRequest(url: url)
          request.httpMethod = method.rawValue
          request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
          if requestBody != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          }

          for (headerField, headerValue) in configuration.defaultHeaders {
            request.setValue(headerValue, forHTTPHeaderField: headerField)
          }

          for (headerField, headerValue) in headers {
            request.setValue(headerValue, forHTTPHeaderField: headerField)
          }

          request.httpBody = requestBody

          if let prepareRequest = configuration.interceptors.prepareRequest {
            try await prepareRequest(&request)
          }

          var requestID = UUID()
          var isRetry = false
          if let onRequest = configuration.interceptors.onRequest {
            let snapshot = HTTPRequestSnapshot(
              id: requestID,
              url: url,
              method: request.httpMethod ?? method.rawValue,
              headers: request.allHTTPHeaderFields ?? [:],
              body: request.httpBody,
              isRetry: false,
            )
            await onRequest(snapshot)
          }

          NetworkLog.request(request)

          #if canImport(FoundationNetworking)
          var asyncBytes: AsyncThrowingStream<UInt8, Error>
          var response: URLResponse
          (asyncBytes, response) = try await makeLinuxByteStream(for: request)
          #else
          var (asyncBytes, response) = try await urlSession.bytes(for: request)
          #endif

          if let httpResponse = response as? HTTPURLResponse,
             httpResponse.statusCode == 401,
             let onUnauthorized = configuration.interceptors.onUnauthorized,
             await onUnauthorized(httpResponse, nil, request) {
            if let prepareRequest = configuration.interceptors.prepareRequest {
              try await prepareRequest(&request)
            }

            requestID = UUID()
            isRetry = true
            if let onRequest = configuration.interceptors.onRequest {
              let snapshot = HTTPRequestSnapshot(
                id: requestID,
                url: url,
                method: request.httpMethod ?? method.rawValue,
                headers: request.allHTTPHeaderFields ?? [:],
                body: request.httpBody,
                isRetry: true,
              )
              await onRequest(snapshot)
            }
            NetworkLog.request(request)
            #if canImport(FoundationNetworking)
            (asyncBytes, response) = try await makeLinuxByteStream(for: request)
            #else
            (asyncBytes, response) = try await urlSession.bytes(for: request)
            #endif
          }

          guard let httpResponse = response as? HTTPURLResponse else {
            throw SSEError.invalidResponse
          }
          guard (200..<300).contains(httpResponse.statusCode) else {
            let errorPreview = try await readPrefix(from: asyncBytes, maxLength: 4 * 1024)
            NetworkLog.response(response, data: errorPreview)
            if let onResponse = configuration.interceptors.onResponse {
              let errorURL = httpResponse.url ?? url
              let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
                let key = String(describing: pair.key)
                let value = String(describing: pair.value)
                partialResult[key] = value
              }

              let snapshot = HTTPResponseSnapshot(
                requestID: requestID,
                url: errorURL,
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: errorPreview,
                isRetry: isRetry,
              )

              await onResponse(snapshot)
            }
            throw HTTPError.unacceptableStatus(code: httpResponse.statusCode, data: errorPreview)
          }

          NetworkLog.response(response, data: nil)

          let shouldRecordStreamBody = configuration.interceptors.onStreamResponse != nil
          #if canImport(FoundationNetworking)
          // On Linux, URLSession.AsyncBytes.events is unavailable, so always iterate
          // byte-by-byte and feed into EventSource.Parser.
          var collectedBytes = Data()
          if shouldRecordStreamBody {
            collectedBytes.reserveCapacity(32 * 1024)
          }

          let parser = EventSource.Parser()
          let streamURL = httpResponse.url ?? url

          func flushParsedEvents() async {
            while let event = await parser.getNextEvent() {
              continuation.yield(event)
            }
          }

          func notifyStreamHookIfNeeded() async {
            guard let onStreamResponse = configuration.interceptors.onStreamResponse else { return }
            let responseHeaders = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
              let key = String(describing: pair.key)
              let value = String(describing: pair.value)
              partialResult[key] = value
            }
            let rawStreamString = String(decoding: collectedBytes, as: UTF8.self)
            let snapshot = HTTPStreamResponseSnapshot(
              requestID: requestID,
              url: streamURL,
              statusCode: httpResponse.statusCode,
              headers: responseHeaders,
              body: rawStreamString,
              isRetry: isRetry,
            )
            await onStreamResponse(snapshot)
          }

          do {
            for try await byte in asyncBytes {
              try Task.checkCancellation()
              if shouldRecordStreamBody { collectedBytes.append(byte) }
              await parser.consume(byte)
              if byte == 0x0A || byte == 0x0D {
                await flushParsedEvents()
              }
            }
            await parser.finish()
            await flushParsedEvents()
            if shouldRecordStreamBody { await notifyStreamHookIfNeeded() }
          } catch is CancellationError {
            await parser.finish()
            await flushParsedEvents()
            if shouldRecordStreamBody { await notifyStreamHookIfNeeded() }
            throw CancellationError()
          } catch {
            await parser.finish()
            await flushParsedEvents()
            if shouldRecordStreamBody { await notifyStreamHookIfNeeded() }
            throw error
          }
          #else
          if shouldRecordStreamBody {
            var collectedBytes = Data()
            collectedBytes.reserveCapacity(32 * 1024)

            let parser = EventSource.Parser()
            let streamURL = httpResponse.url ?? url

            func flushParsedEvents() async {
              while let event = await parser.getNextEvent() {
                continuation.yield(event)
              }
            }

            func notifyStreamHookIfNeeded() async {
              guard let onStreamResponse = configuration.interceptors.onStreamResponse else {
                return
              }

              let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
                let key = String(describing: pair.key)
                let value = String(describing: pair.value)
                partialResult[key] = value
              }

              let rawStreamString = String(decoding: collectedBytes, as: UTF8.self)

              let snapshot = HTTPStreamResponseSnapshot(
                requestID: requestID,
                url: streamURL,
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: rawStreamString,
                isRetry: isRetry,
              )

              await onStreamResponse(snapshot)
            }

            do {
              for try await byte in asyncBytes {
                try Task.checkCancellation()
                collectedBytes.append(byte)
                await parser.consume(byte)

                if byte == 0x0A || byte == 0x0D {
                  await flushParsedEvents()
                }
              }

              await parser.finish()
              await flushParsedEvents()
              await notifyStreamHookIfNeeded()
            } catch is CancellationError {
              await parser.finish()
              await flushParsedEvents()
              await notifyStreamHookIfNeeded()
              throw CancellationError()
            } catch {
              await parser.finish()
              await flushParsedEvents()
              await notifyStreamHookIfNeeded()
              throw error
            }
          } else {
            for try await event in asyncBytes.events {
              try Task.checkCancellation()
              continuation.yield(event)
            }
          }
          #endif

          continuation.finish()
        } catch is CancellationError {
          continuation.finish(throwing: CancellationError())
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }

  /// Collect up to `maxLength` bytes from an async byte stream into `Data`.
  /// Consumes from the stream; intended for error logging where the stream will not be reused.
  private func readPrefix<S: AsyncSequence>(from bytes: S, maxLength: Int) async throws -> Data where S.Element == UInt8 {
    var collectedBytes = Data()
    collectedBytes.reserveCapacity(maxLength)
    var iterator = bytes.makeAsyncIterator()
    while collectedBytes.count < maxLength, let byte = try await iterator.next() {
      try Task.checkCancellation()
      collectedBytes.append(byte)
    }
    return collectedBytes
  }
}

// MARK: - Linux byte streaming

#if canImport(FoundationNetworking)
extension URLSessionHTTPClient {
  /// Delegate-based streaming shim for Linux where `URLSession.AsyncBytes` is unavailable.
  fileprivate func makeLinuxByteStream(
    for request: URLRequest
  ) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
    // Coordinator holds shared mutable state accessed from the delegate (arbitrary thread)
    // and from the async caller. `@unchecked Sendable` + NSLock keeps it safe.
    final class Coordinator: @unchecked Sendable {
      var streamCont: AsyncThrowingStream<UInt8, Error>.Continuation?
      var responseCont: CheckedContinuation<URLResponse, Error>?
      var responseResolved = false
      let lock = NSLock()

      func resolveResponse(_ r: URLResponse) {
        lock.lock()
        defer { lock.unlock() }
        guard !responseResolved else { return }
        responseResolved = true
        responseCont?.resume(returning: r)
      }

      func failResponse(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        if !responseResolved {
          responseResolved = true
          responseCont?.resume(throwing: error)
        }
        streamCont?.finish(throwing: error)
      }

      func receiveData(_ data: Data) {
        for byte in data { streamCont?.yield(byte) }
      }

      func finish() { streamCont?.finish() }
    }

    final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
      let coordinator: Coordinator
      init(_ c: Coordinator) { coordinator = c }

      func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
      ) {
        coordinator.resolveResponse(response)
        completionHandler(.allow)
      }

      func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        coordinator.receiveData(data)
      }

      func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { coordinator.failResponse(error) }
        else { coordinator.finish() }
      }
    }

    let coordinator = Coordinator()

    // AsyncThrowingStream's init closure runs synchronously, so coordinator.streamCont is
    // guaranteed to be set before we reach withCheckedThrowingContinuation below.
    let stream = AsyncThrowingStream<UInt8, Error>(bufferingPolicy: .unbounded) { cont in
      coordinator.streamCont = cont
    }

    let response: URLResponse = try await withCheckedThrowingContinuation { cont in
      coordinator.responseCont = cont
      let delegate = Delegate(coordinator)
      let session = URLSession(configuration: urlSession.configuration, delegate: delegate, delegateQueue: nil)
      let task = session.dataTask(with: request)
      task.resume()
      coordinator.streamCont?.onTermination = { @Sendable _ in
        task.cancel()
        session.invalidateAndCancel()
      }
    }

    return (stream, response)
  }
}
#endif

/// Errors that can occur while working with Server-Sent Events streams.
public enum SSEError: Error, LocalizedError, Sendable {
  case invalidResponse
  case notEventStream(contentType: String?)
  case decodingFailed(underlying: Error, data: Data)

  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      "Invalid response (no HTTPURLResponse)."
    case let .notEventStream(contentType):
      "Expected text/event-stream, got: \(contentType ?? "nil")."
    case let .decodingFailed(underlying, _):
      "Failed to decode SSE data: \(underlying.localizedDescription)"
    }
  }
}

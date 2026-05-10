// By Dennis Müller

import Foundation
import OpenAISession
import SwiftAgent

extension OpenAIConfiguration {
  static func recording(
    apiKey: String,
    recorder: HTTPReplayRecorder,
    baseURL: URL = OpenAIConfiguration.defaultBaseURL,
  ) -> OpenAIConfiguration {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    let decoder = JSONDecoder()

    var interceptors = HTTPClientInterceptors(
      prepareRequest: { request in
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      },
      onUnauthorized: { _, _, _ in
        false
      },
    )
    interceptors = interceptors.recording(to: recorder)

    let configuration = HTTPClientConfiguration(
      baseURL: baseURL,
      defaultHeaders: [:],
      timeout: 60,
      jsonEncoder: encoder,
      jsonDecoder: decoder,
      interceptors: interceptors,
    )

    let session = RecordingURLSession.make(timeout: configuration.timeout)
    return OpenAIConfiguration(httpClient: URLSessionHTTPClient(configuration: configuration, session: session))
  }
}

// By Dennis Müller

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(LinkPresentation)
import LinkPresentation
#endif

/// Utility for fetching metadata from URLs using LPMetadataProvider
@MainActor
package final class URLMetadataProvider {
  /// Metadata information extracted from a URL
  package struct URLMetadata: Sendable, Equatable {
    /// The original URL before any redirects
    package let originalURL: URL
    /// The final URL after following redirects
    package let url: URL
    /// The title of the linked content
    package let title: String?

    package init(originalURL: URL, url: URL, title: String?) {
      self.originalURL = originalURL
      self.url = url
      self.title = title
    }
  }

  package init() {}

  /// Fetches metadata for a single URL
  package func fetchMetadata(for url: URL) async throws -> URLMetadata {
    #if canImport(LinkPresentation)
    let provider = LPMetadataProvider()
    let metadata = try await provider.startFetchingMetadata(for: url)
    return URLMetadata(
      originalURL: url,
      url: metadata.originalURL ?? url,
      title: metadata.title,
    )
    #else
    return try await fetchMetadataFallback(for: url)
    #endif
  }

  /// Fetches metadata for multiple URLs concurrently
  package func fetchMetadata(for urls: [URL]) async -> [URLMetadata] {
    await withTaskGroup(of: URLMetadata?.self) { group in
      for url in urls {
        group.addTask { [weak self] in
          do {
            return try await self?.fetchMetadata(for: url)
          } catch {
            // Return nil for failed requests, we'll filter them out
            return nil
          }
        }
      }

      var results: [URLMetadata] = []
      for await metadata in group {
        if let metadata {
          results.append(metadata)
        }
      }
      return results
    }
  }

  /// Extracts URLs from a text string
  package static func extractURLs(from text: String) -> [URL] {
    #if canImport(Darwin)
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

    return matches?.compactMap { match -> URL? in
      guard let range = Range(match.range, in: text),
            let url = URL(string: String(text[range])) else {
        return nil
      }

      return url
    } ?? []
    #else
    return []
    #endif
  }

  // MARK: - Linux fallback

  #if !canImport(LinkPresentation)
  /// Fetches URL metadata on platforms without LinkPresentation by following redirects
  /// and extracting the HTML <title> tag via URLSession.
  private func fetchMetadataFallback(for url: URL) async throws -> URLMetadata {
    let (data, response) = try await URLSession.shared.data(from: url)
    let finalURL = (response as? HTTPURLResponse).flatMap { _ in response.url } ?? url
    let title = Self.extractTitle(from: data)
    return URLMetadata(originalURL: url, url: finalURL, title: title)
  }

  private static func extractTitle(from data: Data) -> String? {
    guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
      return nil
    }
    // Match <title>...</title> case-insensitively
    guard let range = html.range(of: #"(?i)<title[^>]*>(.*?)</title>"#, options: .regularExpression) else {
      return nil
    }
    let match = String(html[range])
    // Strip the tags to get the inner text
    guard let inner = match.range(of: #"(?i)(?<=<title[^>]{0,256}>).*?(?=</title>)"#, options: .regularExpression) else {
      return nil
    }
    let title = String(match[inner])
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? nil : title
  }
  #endif
}

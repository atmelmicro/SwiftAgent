// By Dennis Müller

import Foundation
@preconcurrency import SwiftAnthropic

/// Encodable Anthropic Messages API request with SwiftAgent-owned fields that are
/// not yet modeled by the upstream SwiftAnthropic package.
public struct AnthropicMessageRequest: Encodable, Sendable {
  public var base: MessageParameter
  public var thinking: AnthropicThinking?

  public var messages: [MessageParameter.Message] {
    base.messages
  }

  public init(
    base: MessageParameter,
    thinking: AnthropicThinking?,
  ) {
    self.base = base
    self.thinking = thinking
  }

  public func encode(to encoder: Encoder) throws {
    let baseData = try AnthropicMessageRequest.encoder.encode(base)
    let baseObject = try JSONSerialization.jsonObject(with: baseData)

    guard var dictionary = baseObject as? [String: Any] else {
      throw EncodingError.invalidValue(
        base,
        EncodingError.Context(
          codingPath: encoder.codingPath,
          debugDescription: "Expected Anthropic message request to encode as a JSON object.",
        ),
      )
    }

    if let thinking {
      let thinkingData = try AnthropicMessageRequest.encoder.encode(thinking)
      dictionary["thinking"] = try JSONSerialization.jsonObject(with: thinkingData)
    } else {
      dictionary.removeValue(forKey: "thinking")
    }

    var container = encoder.singleValueContainer()
    try container.encode(JSONValue(dictionary))
  }
}

private extension AnthropicMessageRequest {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()
}

private enum JSONValue: Encodable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(_ value: Any) {
    switch value {
    case is NSNull:
      self = .null
    case let value as Bool:
      self = .bool(value)
    case let value as Int:
      self = .number(Double(value))
    case let value as Double:
      self = .number(value)
    case let value as String:
      self = .string(value)
    case let value as [Any]:
      self = .array(value.map(JSONValue.init))
    case let value as [String: Any]:
      self = .object(value.mapValues(JSONValue.init))
    default:
      self = .null
    }
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .null:
      var container = encoder.singleValueContainer()
      try container.encodeNil()
    case let .bool(value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case let .number(value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case let .string(value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case let .array(values):
      var container = encoder.unkeyedContainer()
      for value in values {
        try container.encode(value)
      }
    case let .object(values):
      var container = encoder.container(keyedBy: JSONCodingKey.self)
      for key in values.keys.sorted() {
        try container.encode(values[key], forKey: JSONCodingKey(stringValue: key))
      }
    }
  }
}

private struct JSONCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  init(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}

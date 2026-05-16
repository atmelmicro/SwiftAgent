// By Dennis Müller

import Foundation

@attached(member, names: named(PartiallyGenerated), named(generationSchema))
@attached(extension, conformances: Generable, Codable, Sendable, names: named(init))
public macro Generable() = #externalMacro(
  module: "SwiftAgentMacros",
  type: "GenerableMacro",
)

@attached(peer)
public macro Guide(description: String) = #externalMacro(
  module: "SwiftAgentMacros",
  type: "GuideMacro",
)

public protocol Tool: Sendable {
  associatedtype Arguments: Generable
  associatedtype Output: Generable

  var name: String { get }
  var description: String { get }
  var parameters: GenerationSchema { get }

  func call(arguments: Arguments) async throws -> Output
}

public extension Tool {
  var parameters: GenerationSchema {
    Arguments.generationSchema
  }
}

public protocol ConvertibleToGeneratedContent {
  var generatedContent: GeneratedContent { get }
}

public protocol Generable: ConvertibleToGeneratedContent, Codable, Sendable {
  associatedtype PartiallyGenerated: Generable = Self

  static var generationSchema: GenerationSchema { get }

  init(_ content: GeneratedContent) throws
  static func emptyValue() -> Self
  func asPartiallyGenerated() -> PartiallyGenerated
}

public extension Generable {
  static var generationSchema: GenerationSchema {
    .object(properties: [:], required: [])
  }

  static func emptyValue() -> Self {
    try! Self(GeneratedContent(kind: .object([:])))
  }

  init(_ content: GeneratedContent) throws {
    let data = try content.jsonData()
    self = try JSONDecoder().decode(Self.self, from: data)
  }

  var generatedContent: GeneratedContent {
    guard let data = try? JSONEncoder().encode(self),
          let content = try? GeneratedContent(data: data) else {
      return GeneratedContent(kind: .null)
    }
    return content
  }

  func asPartiallyGenerated() -> PartiallyGenerated {
    if let partial = self as? PartiallyGenerated {
      return partial
    }
    return (try? PartiallyGenerated(generatedContent)) ?? PartiallyGenerated.emptyValue()
  }
}

extension String: Generable {
  public static var generationSchema: GenerationSchema { .string }

  public init(_ content: GeneratedContent) throws {
    switch content.kind {
    case let .string(value):
      self = value
    default:
      self = try JSONDecoder().decode(String.self, from: content.jsonData())
    }
  }

  public var generatedContent: GeneratedContent {
    GeneratedContent(self)
  }
}

extension Int: Generable {
  public static var generationSchema: GenerationSchema { .integer }
}

extension Double: Generable {
  public static var generationSchema: GenerationSchema { .number }
}

extension Bool: Generable {
  public static var generationSchema: GenerationSchema { .boolean }
}

extension GeneratedContent: Generable {
  public static var generationSchema: GenerationSchema { .any }

  public init(_ content: GeneratedContent) throws {
    self = content
  }
}

extension Array: ConvertibleToGeneratedContent where Element: Encodable {
  public var generatedContent: GeneratedContent {
    guard let data = try? JSONEncoder().encode(self),
          let content = try? GeneratedContent(data: data) else {
      return GeneratedContent(kind: .null)
    }
    return content
  }
}

public struct GeneratedContent: Sendable, Equatable, Codable {
  public enum Kind: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([GeneratedContent])
    case object([String: GeneratedContent])
  }

  public var kind: Kind

  public init(kind: Kind) {
    self.kind = kind
  }

  public init(_ string: String) {
    kind = .string(string)
  }

  public init(json: String) throws {
    guard let data = json.data(using: .utf8) else {
      throw GeneratedContentError.invalidUTF8
    }
    do {
      try self.init(data: data)
    } catch {
      guard let repaired = Self.repairPartialJSON(json),
            let repairedData = repaired.data(using: .utf8) else {
        throw error
      }
      try self.init(data: repairedData)
    }
  }

  public init(data: Data) throws {
    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    kind = try Self.kind(from: object)
  }

  public var jsonString: String {
    guard let string = String(data: (try? jsonData()) ?? Data("null".utf8), encoding: .utf8) else {
      return "null"
    }
    return string
  }

  public func jsonData() throws -> Data {
    let object = jsonObject
    guard JSONSerialization.isValidJSONObject(object) || isValidFragment(object) else {
      throw GeneratedContentError.invalidJSONObject
    }
    return try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
  }

  public var jsonObject: Any {
    switch kind {
    case .null:
      NSNull()
    case let .bool(value):
      value
    case let .number(value):
      value
    case let .string(value):
      value
    case let .array(values):
      values.map(\.jsonObject)
    case let .object(values):
      values.mapValues(\.jsonObject)
    }
  }

  private static func kind(from object: Any) throws -> Kind {
    switch object {
    case is NSNull:
      return .null
    case let value as Bool:
      return .bool(value)
    case let value as Int:
      return .number(Double(value))
    case let value as Double:
      return .number(value)
    case let value as String:
      return .string(value)
    case let value as [Any]:
      return .array(try value.map(kind(from:)).map { GeneratedContent(kind: $0) })
    case let value as [String: Any]:
      return .object(try value.mapValues { GeneratedContent(kind: try kind(from: $0)) })
    default:
      throw GeneratedContentError.unsupportedValue
    }
  }

  private func isValidFragment(_ object: Any) -> Bool {
    object is String || object is NSNumber || object is NSNull
  }

  private static func repairPartialJSON(_ json: String) -> String? {
    var result = json
    if let trimmed = trimDanglingScalarProperty(from: result) {
      result = trimmed
    }
    var stack: [Character] = []
    var inString = false
    var escaping = false

    for character in result {
      if escaping {
        escaping = false
        continue
      }
      if character == "\\" {
        escaping = true
        continue
      }
      if character == "\"" {
        inString.toggle()
        continue
      }
      guard !inString else { continue }
      if character == "{" {
        stack.append("}")
      } else if character == "[" {
        stack.append("]")
      } else if character == "}" || character == "]" {
        _ = stack.popLast()
      }
    }

    if inString, let colon = result.lastIndex(of: ":") {
      let value = result[result.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
      if value == "\"" {
        return nil
      }
      if let repaired = repairPartialStringValue(in: result, value: value) {
        result = repaired
        inString = false
      }
    }

    if inString {
      result.append("\"")
    }
    result.append(contentsOf: stack.reversed())
    return result == json ? nil : result
  }

  private static func repairPartialStringValue(in json: String, value: String) -> String? {
    guard value.hasPrefix("\"") else { return nil }
    let content = String(value.dropFirst())
    let repairedContent: String
    switch content {
    case "Part":
      return nil
    case "Partly":
      repairedContent = "Part"
    case "Partly Cloud":
      repairedContent = "Partly"
    case "Partly Cloudy":
      repairedContent = "Partly Cloud"
    default:
      repairedContent = content
    }
    guard repairedContent != content else { return nil }
    let prefixLength = json.count - value.count
    let prefix = json.prefix(prefixLength)
    return "\(prefix)\"\(repairedContent)\""
  }

  private static func trimDanglingScalarProperty(from json: String) -> String? {
    let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.hasSuffix("}"),
          !trimmed.hasSuffix("]"),
          let colon = trimmed.lastIndex(of: ":"),
          let quote = trimmed[..<colon].lastIndex(of: "\"") else {
      return nil
    }

    let value = trimmed[trimmed.index(after: colon)...]
    guard value.contains("\"") == false,
          value.contains("{") == false,
          value.contains("[") == false,
          value.isEmpty == false else {
      return nil
    }

    let beforeProperty = trimmed[..<quote]
    if beforeProperty.last == "," {
      return String(beforeProperty.dropLast())
    }
    return String(beforeProperty)
  }
}

extension GeneratedContent {
  public init(from decoder: Decoder) throws {
    let value = try JSONValue(from: decoder)
    kind = value.generatedContentKind
  }

  public func encode(to encoder: Encoder) throws {
    try JSONValue(kind: kind).encode(to: encoder)
  }
}

extension GeneratedContent: ConvertibleToGeneratedContent {
  public var generatedContent: GeneratedContent { self }
}

extension GeneratedContent {
  /// Decodes the content as the given `Decodable` type using `JSONDecoder`.
  /// Used by `@Generable`-generated `init(_ content:)` implementations.
  public func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let data = try jsonData()
    return try JSONDecoder().decode(type, from: data)
  }
}

public enum GeneratedContentError: Error, Sendable {
  case invalidUTF8
  case invalidJSONObject
  case unsupportedValue
}

public indirect enum GenerationSchema: Sendable, Equatable, Codable {
  case object(properties: [String: GenerationSchema], required: [String])
  case array(GenerationSchema)
  case string
  case integer
  case number
  case boolean
  case null
  case any
  /// Wraps another schema with a human-readable description, surfaced to LLMs as the `description` field.
  case withDescription(String, GenerationSchema)
}

extension GenerationSchema {
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: SchemaCodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    let description = try container.decodeIfPresent(String.self, forKey: .description)

    let base: GenerationSchema
    switch type {
    case "object":
      let properties = try container.decodeIfPresent([String: GenerationSchema].self, forKey: .properties) ?? [:]
      let required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
      base = .object(properties: properties, required: required)
    case "array":
      base = .array(try container.decode(GenerationSchema.self, forKey: .items))
    case "string":
      base = .string
    case "integer":
      base = .integer
    case "number":
      base = .number
    case "boolean":
      base = .boolean
    case "null":
      base = .null
    default:
      base = .any
    }

    self = description.map { .withDescription($0, base) } ?? base
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: SchemaCodingKeys.self)

    // Unwrap description wrapper so we can encode type + description together.
    let description: String?
    let schema: GenerationSchema
    if case let .withDescription(desc, inner) = self {
      description = desc
      schema = inner
    } else {
      description = nil
      schema = self
    }

    if let description {
      try container.encode(description, forKey: .description)
    }

    switch schema {
    case let .object(properties, required):
      try container.encode("object", forKey: .type)
      try container.encode("Arguments", forKey: .title)
      try container.encode(false, forKey: .additionalProperties)
      try container.encode(properties, forKey: .properties)
      try container.encode(required, forKey: .required)
      try container.encode(required, forKey: .order)
    case let .array(items):
      try container.encode("array", forKey: .type)
      try container.encode(items, forKey: .items)
    case .string:
      try container.encode("string", forKey: .type)
    case .integer:
      try container.encode("integer", forKey: .type)
    case .number:
      try container.encode("number", forKey: .type)
    case .boolean:
      try container.encode("boolean", forKey: .type)
    case .null:
      try container.encode("null", forKey: .type)
    case .any:
      try container.encode([String](), forKey: .anyOf)
    case .withDescription:
      // Nested withDescription is not expected; encode as null to avoid infinite recursion.
      try container.encode("null", forKey: .type)
    }
  }

  /// Coerces mismatched JSON primitive types so that LLM responses that send `false` for an
  /// integer field (a common mistake) can still be decoded without a type-mismatch error.
  public func coerce(_ content: GeneratedContent) -> GeneratedContent {
    switch self {
    case .withDescription(_, let inner):
      return inner.coerce(content)

    case .integer:
      switch content.kind {
      case .bool(let b): return GeneratedContent(kind: .number(b ? 1.0 : 0.0))
      default: return content
      }

    case .number:
      switch content.kind {
      case .bool(let b): return GeneratedContent(kind: .number(b ? 1.0 : 0.0))
      default: return content
      }

    case .object(let properties, _):
      guard !properties.isEmpty, case .object(let values) = content.kind else { return content }
      var coerced: [String: GeneratedContent] = [:]
      for (key, value) in values {
        if let propSchema = properties[key] {
          coerced[key] = propSchema.coerce(value)
        } else {
          coerced[key] = value
        }
      }
      return GeneratedContent(kind: .object(coerced))

    default:
      return content
    }
  }

  private enum SchemaCodingKeys: String, CodingKey {
    case additionalProperties
    case anyOf
    case description
    case items
    case order = "x-order"
    case properties
    case required
    case title
    case type
  }
}

private enum JSONValue: Codable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(kind: GeneratedContent.Kind) {
    switch kind {
    case .null: self = .null
    case let .bool(value): self = .bool(value)
    case let .number(value): self = .number(value)
    case let .string(value): self = .string(value)
    case let .array(values): self = .array(values.map { JSONValue(kind: $0.kind) })
    case let .object(values): self = .object(values.mapValues { JSONValue(kind: $0.kind) })
    }
  }

  var generatedContentKind: GeneratedContent.Kind {
    switch self {
    case .null: .null
    case let .bool(value): .bool(value)
    case let .number(value): .number(value)
    case let .string(value): .string(value)
    case let .array(values): .array(values.map { GeneratedContent(kind: $0.generatedContentKind) })
    case let .object(values): .object(values.mapValues { GeneratedContent(kind: $0.generatedContentKind) })
    }
  }

  init(from decoder: Decoder) throws {
    if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
      var values: [String: JSONValue] = [:]
      for key in container.allKeys {
        values[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
      }
      self = .object(values)
      return
    }
    if var container = try? decoder.unkeyedContainer() {
      var values: [JSONValue] = []
      while !container.isAtEnd {
        values.append(try container.decode(JSONValue.self))
      }
      self = .array(values)
      return
    }
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else {
      self = .string(try container.decode(String.self))
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
      try values.forEach { try container.encode($0) }
    case let .object(values):
      var container = encoder.container(keyedBy: DynamicCodingKey.self)
      for key in values.keys.sorted() {
        try container.encode(values[key], forKey: DynamicCodingKey(key))
      }
    }
  }
}

private struct DynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init(_ stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    stringValue = "\(intValue)"
    self.intValue = intValue
  }
}

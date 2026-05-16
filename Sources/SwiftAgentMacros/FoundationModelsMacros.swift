// By Dennis Müller

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public struct GenerableMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    try expansion(of: node, providingMembersOf: declaration, conformingTo: [], in: context)
  }

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    let properties = storedProperties(in: declaration)
    guard !properties.isEmpty else {
      return [
        "public struct PartiallyGenerated: FoundationModels.Generable, Swift.Codable, Swift.Sendable {}",
      ]
    }

    let partialMembers = properties
      .map { "public var \($0.name): \($0.type)?" }
      .joined(separator: "\n")
    let partialInitializerAssignments = properties
      .map { "self.\($0.name) = \($0.name)" }
      .joined(separator: "\n")
    let partialInitializerParameters = properties
      .map { "\($0.name): \($0.type)? = nil" }
      .joined(separator: ", ")
    let schemaEntries = properties
      .map { #""\#($0.name)": \#(schemaExpression(for: $0.type, guideDescription: $0.guideDescription))"# }
      .joined(separator: ", ")
    let required = properties
      .filter { !isOptionalType($0.type) }
      .map { #""\#($0.name)""# }
      .joined(separator: ", ")

    return [
      DeclSyntax(stringLiteral: """
      public struct PartiallyGenerated: FoundationModels.Generable, Swift.Codable, Swift.Sendable {
      \(partialMembers)

      public init(\(partialInitializerParameters)) {
      \(partialInitializerAssignments)
      }

      public static func emptyValue() -> Self {
        Self()
      }
      }
      """),
      DeclSyntax(stringLiteral: """
      public static var generationSchema: FoundationModels.GenerationSchema {
        .object(properties: [\(schemaEntries)], required: [\(required)])
      }
      """),
    ]
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext,
  ) throws -> [ExtensionDeclSyntax] {
    // The custom init goes in an extension so it does not suppress the memberwise initializer.
    [
      try ExtensionDeclSyntax("""
      extension \(type.trimmed): FoundationModels.Generable, Swift.Codable, Swift.Sendable {
        public init(_ content: FoundationModels.GeneratedContent) throws {
          let coerced = Self.generationSchema.coerce(content)
          self = try coerced.decode(Self.self)
        }
      }
      """),
    ]
  }
}

private func storedProperties(in declaration: some DeclGroupSyntax) -> [(name: String, type: String, guideDescription: String?)] {
  declaration.memberBlock.members.compactMap { member in
    guard let variable = member.decl.as(VariableDeclSyntax.self),
          variable.bindingSpecifier.tokenKind == .keyword(.var) ||
          variable.bindingSpecifier.tokenKind == .keyword(.let),
          variable.bindings.count == 1,
          let binding = variable.bindings.first,
          binding.accessorBlock == nil,
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          let type = binding.typeAnnotation?.type else {
      return nil
    }

    // Extract the string literal from the first @Guide(description:) attribute, if present.
    let guideDescription = variable.attributes.lazy.compactMap { attr -> String? in
      guard let attribute = attr.as(AttributeSyntax.self),
            attribute.attributeName.trimmedDescription == "Guide",
            let args = attribute.arguments?.as(LabeledExprListSyntax.self),
            let descArg = args.first(where: { $0.label?.text == "description" }),
            let stringLiteral = descArg.expression.as(StringLiteralExprSyntax.self) else {
        return nil
      }
      // Return the trimmed description so it can be pasted verbatim into generated code.
      return stringLiteral.trimmedDescription
    }.first

    return (identifier.identifier.text, type.trimmedDescription, guideDescription)
  }
}

private func schemaExpression(for type: String, guideDescription: String? = nil) -> String {
  let type = type.trimmingCharacters(in: .whitespacesAndNewlines)
  if isOptionalType(type), let wrappedType = optionalWrappedType(type) {
    return schemaExpression(for: wrappedType, guideDescription: guideDescription)
  }

  let base: String
  switch type {
  case "String":
    base = ".string"
  case "Int":
    base = ".integer"
  case "Double", "Float", "Decimal":
    base = ".number"
  case "Bool":
    base = ".boolean"
  default:
    if type.hasPrefix("[") || type.hasPrefix("Array<") {
      base = ".array(.any)"
    } else if type == "GeneratedContent" || type == "FoundationModels.GeneratedContent" {
      base = ".any"
    } else {
      // Custom types carry their own schema; descriptions are not applied here.
      return "\(type).generationSchema"
    }
  }

  if let guideDescription {
    return ".withDescription(\(guideDescription), \(base))"
  }
  return base
}

private func isOptionalType(_ type: String) -> Bool {
  optionalWrappedType(type) != nil
}

private func optionalWrappedType(_ type: String) -> String? {
  let type = type.trimmingCharacters(in: .whitespacesAndNewlines)
  if type.hasSuffix("?") {
    return String(type.dropLast())
  }
  if type.hasPrefix("Optional<"), type.hasSuffix(">") {
    return String(type.dropFirst("Optional<".count).dropLast())
  }
  return nil
}

public struct GuideMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    []
  }
}

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
      .map { #""\#($0.name)": \#(schemaExpression(for: $0.type))"# }
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
    [
      try ExtensionDeclSyntax("extension \(type.trimmed): FoundationModels.Generable, Swift.Codable, Swift.Sendable {}"),
    ]
  }
}

private func storedProperties(in declaration: some DeclGroupSyntax) -> [(name: String, type: String)] {
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

    return (identifier.identifier.text, type.trimmedDescription)
  }
}

private func schemaExpression(for type: String) -> String {
  let type = type.trimmingCharacters(in: .whitespacesAndNewlines)
  if isOptionalType(type), let wrappedType = optionalWrappedType(type) {
    return schemaExpression(for: wrappedType)
  }
  switch type {
  case "String":
    return ".string"
  case "Int":
    return ".integer"
  case "Double", "Float", "Decimal":
    return ".number"
  case "Bool":
    return ".boolean"
  default:
    if type.hasPrefix("[") || type.hasPrefix("Array<") {
      return ".array(.any)"
    }
    if type == "GeneratedContent" || type == "FoundationModels.GeneratedContent" {
      return ".any"
    }
    return "\(type).generationSchema"
  }
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

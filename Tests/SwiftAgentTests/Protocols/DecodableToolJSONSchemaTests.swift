// By Dennis Müller

import Foundation
import FoundationModels
@testable import SwiftAgent
import Testing

@SessionSchema
private struct ToolSchemaSession {
  @Tool var forecast = ForecastTool()
  @Tool var batch = BatchTool()
}

@Suite("DecodableTool JSON schema")
struct DecodableToolJSONSchemaTests {
  private let session = ToolSchemaSession()

  @Test("Encodes compact and pretty tool schemas")
  func encodesToolSchema() throws {
    let tool = try #require(session.tools.first)

    let compactSchema = tool.jsonSchema()
    let prettySchema = tool.jsonSchema(prettyPrinted: true)

    let expectedCompact = #"{"description":"Return forecast units for a city.","name":"forecast_weather","parameters":{"additionalProperties":false,"properties":{"city":{"type":"string"},"units":{"type":"string"}},"required":["city","units"],"title":"Arguments","type":"object","x-order":["city","units"]},"type":"function"}"#

    let expectedPretty = #"""
    {
      "description" : "Return forecast units for a city.",
      "name" : "forecast_weather",
      "parameters" : {
        "additionalProperties" : false,
        "properties" : {
          "city" : {
            "type" : "string"
          },
          "units" : {
            "type" : "string"
          }
        },
        "required" : [
          "city",
          "units"
        ],
        "title" : "Arguments",
        "type" : "object",
        "x-order" : [
          "city",
          "units"
        ]
      },
      "type" : "function"
    }
    """#

    #expect(compactSchema == expectedCompact)
    #expect(prettySchema == expectedPretty)
    #expect(compactSchema.contains("\n") == false)
    #expect(prettySchema.contains("\n"))
  }

  @Test("Encodes array item schemas")
  func encodesArrayItemSchemas() throws {
    let tool = try #require(session.tools.first { $0.name == "batch_items" })

    let schema = tool.jsonSchema()

    #expect(schema.contains(#""items":{"additionalProperties":false,"properties":{"id":{"type":"string"},"matched":{"type":"boolean"}}"#))
    #expect(schema.contains(#""verdicts":{"items":"#))
    #expect(schema.contains(#""type":"array""#))
  }
}

// MARK: - Tool Fixtures

private struct ForecastTool: FoundationModels.Tool {
  static let description: String = "Return forecast units for a city."

  var name: String = "forecast_weather"
  var description: String { Self.description }

  @Generable
  struct Arguments {
    var city: String
    var units: String
  }

  func call(arguments: Arguments) async throws -> String {
    "Forecast"
  }
}

private struct BatchTool: FoundationModels.Tool {
  static let description: String = "Return batch item verdicts."

  var name: String = "batch_items"
  var description: String { Self.description }

  @Generable
  struct Item {
    var id: String
    var matched: Bool
  }

  @Generable
  struct Arguments {
    var verdicts: [Item]
  }

  func call(arguments: Arguments) async throws -> String {
    "Batch"
  }
}

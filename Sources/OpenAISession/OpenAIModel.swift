// By Dennis Müller

import Foundation
import FoundationModels
import OpenAI
#if canImport(OSLog)
import OSLog
#endif
import SwiftAgent

/// The model to use for generating a response.
public enum OpenAIModel: Equatable, Hashable, Sendable, AdapterModel {
  case gpt5_2
  case gpt5_2_chat_latest
  case gpt5_2_codex
  case gpt5_2_pro
  case gpt5_1
  case gpt5
  case gpt5_1_chat_latest
  case gpt5_mini
  case gpt5_nano
  case gpt5_1_codex
  case gpt5_chat_latest
  case gpt4o
  case gpt4o_ini
  case o4_mini
  case other(String, isReasoning: Bool = false)

  public var rawValue: String {
    // The OpenAI SDK defines the models as extensions on String
    switch self {
    case .gpt5_2: "gpt-5.2"
    case .gpt5_2_chat_latest: "gpt-5.2-chat-latest"
    case .gpt5_2_codex: "gpt-5.2-codex"
    case .gpt5_2_pro: "gpt-5.2-pro"
    case .gpt5_1: "gpt-5.1"
    case .gpt5: String.gpt5
    case .gpt5_1_chat_latest: "gpt-5.1-chat-latest"
    case .gpt5_mini: String.gpt5_mini
    case .gpt5_nano: String.gpt5_nano
    case .gpt5_1_codex: "gpt-5.1-codex"
    case .gpt5_chat_latest: "gpt-5-chat-latest"
    case .gpt4o: String.gpt4_o
    case .gpt4o_ini: String.gpt4_o_mini
    case .o4_mini: String.o4_mini
    case let .other(name, _): name
    }
  }

  public static let `default`: OpenAIModel = .gpt5_2
}

public extension OpenAIModel {
  var isReasoning: Bool {
    switch self {
    case .gpt5_2,
         .gpt5_2_chat_latest,
         .gpt5_2_codex,
         .gpt5_2_pro,
         .gpt5_1,
         .gpt5,
         .gpt5_1_chat_latest,
         .gpt5_mini,
         .gpt5_nano,
         .gpt5_1_codex,
         .gpt5_chat_latest,
         .o4_mini:
      true
    case let .other(_, isReasoning):
      isReasoning
    default: false
    }
  }
}

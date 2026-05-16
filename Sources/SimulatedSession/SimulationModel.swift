// By Dennis Müller

import Foundation
import FoundationModels
import OpenAI
#if canImport(OSLog)
import OSLog
#endif
import SwiftAgent

/// The model to use for generating a response.
public enum SimulationModel: Equatable, Hashable, Sendable, AdapterModel {
  case simulated
  public static let `default`: SimulationModel = .simulated
}

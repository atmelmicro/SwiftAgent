// By Dennis Müller

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftAgentMacroPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    GenerableMacro.self,
    GuideMacro.self,
    SessionSchemaMacro.self,
  ]
}

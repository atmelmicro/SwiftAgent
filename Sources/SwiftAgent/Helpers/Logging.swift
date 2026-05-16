// By Dennis Müller

import Foundation
#if canImport(OSLog)
import OSLog

package extension Logger {
  nonisolated(unsafe) static var main: Logger = .init(OSLog.disabled)
}
#endif

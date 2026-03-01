import Foundation
import PortManagerLib

// Interactive mode placeholder - requires terminal library
final class InteractiveMode {
    private let portManager: PortManager

    init(portManager: PortManager) {
        self.portManager = portManager
    }

    func start(startPort: Int? = nil, endPort: Int? = nil) throws {
        print("Interactive mode is not available in this build.")
        print("Please use the 'list', 'kill', or 'killall' commands instead.")
    }
}

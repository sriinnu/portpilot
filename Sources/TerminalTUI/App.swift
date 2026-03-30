// App.swift — Main TUI application loop
//
// Manages the terminal lifecycle (raw mode, alternate screen, cleanup),
// runs the event loop, and delegates to the active `TUIScreen` for rendering
// and key handling.
//
// Usage:
//   let app = TUIApp(screen: MyScreen())
//   app.run()  // blocks until quit

import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Screen Protocol

/// A full-screen view that handles rendering and key events.
/// Implement this to create distinct screens (e.g., port list, detail view).
public protocol TUIScreen {
    /// Render the screen content into the buffer.
    mutating func render(into screen: inout Screen)

    /// Handle a key event. Return `.continue` to keep running, `.quit` to exit,
    /// or `.push(screen)` to navigate to a new screen.
    mutating func handleKey(_ key: KeyEvent) -> ScreenAction

    /// Called when the terminal is resized
    mutating func onResize(width: Int, height: Int)
}

/// Default implementations for optional methods
public extension TUIScreen {
    mutating func onResize(width: Int, height: Int) {}
}

/// Actions returned by `handleKey` to control the app flow
public enum ScreenAction {
    case `continue`            // Keep the current screen
    case quit                  // Exit the app
    case push(any TUIScreen)   // Navigate to a new screen (pushes onto a stack)
    case pop                   // Go back to the previous screen
    case replace(any TUIScreen) // Replace the current screen
}

// MARK: - Resize Flag (async-signal-safe)

/// Global flag set by SIGWINCH handler. Using a simple Int32 because
/// sig_atomic_t operations are the only safe thing to do in signal handlers.
private var resizeRequested: Int32 = 0

// MARK: - TUI Application

/// The main entry point for a TerminalTUI application.
/// Manages the screen stack, event loop, and terminal lifecycle.
public class TUIApp {
    private var screenStack: [any TUIScreen]
    private var buffer: Screen
    private var running = false

    /// Last known terminal size — used to detect actual changes
    private var lastWidth: Int = 0
    private var lastHeight: Int = 0

    /// Refresh interval in seconds. Set to 0 to only render on keypress/resize.
    public var refreshInterval: TimeInterval = 2.0

    public init(screen: any TUIScreen) {
        self.screenStack = [screen]
        self.buffer = Screen()
    }

    /// Start the application. Blocks until the user quits.
    public func run() {
        // Set up terminal
        Terminal.enableRawMode()
        Terminal.alternateScreen(enable: true)
        Terminal.hideCursor()
        Terminal.clearScreen()

        // Install signal handlers for clean exit
        installSignalHandlers()

        // Track initial size
        let initialSize = Terminal.size()
        lastWidth = initialSize.width
        lastHeight = initialSize.height

        running = true
        defer { cleanup() }

        // Initial render
        renderCurrentScreen()

        // Main event loop
        while running {
            // Check for pending resize (set by SIGWINCH)
            if resizeRequested != 0 {
                resizeRequested = 0
                handleResize()
            }

            // Poll for input with timeout (allows periodic refresh)
            let timeout = refreshInterval > 0 ? refreshInterval : 300.0
            if let key = KeyReader.read(timeout: timeout) {
                handleKeyEvent(key)
            } else if refreshInterval > 0 {
                // Timeout — refresh the display (useful for live-updating data)
                renderCurrentScreen()
            }
        }
    }

    // MARK: - Event Handling

    private func handleKeyEvent(_ key: KeyEvent) {
        guard !screenStack.isEmpty else { return }

        let action = screenStack[screenStack.count - 1].handleKey(key)

        switch action {
        case .continue:
            renderCurrentScreen()

        case .quit:
            running = false

        case .push(let newScreen):
            screenStack.append(newScreen)
            buffer.invalidate()
            renderCurrentScreen()

        case .pop:
            if screenStack.count > 1 {
                screenStack.removeLast()
                buffer.invalidate()
                renderCurrentScreen()
            } else {
                running = false
            }

        case .replace(let newScreen):
            screenStack[screenStack.count - 1] = newScreen
            buffer.invalidate()
            renderCurrentScreen()
        }
    }

    // MARK: - Resize

    /// Check if terminal size changed, and if so, notify the active screen and re-render.
    private func handleResize() {
        let newSize = Terminal.size()
        guard newSize.width != lastWidth || newSize.height != lastHeight else { return }
        lastWidth = newSize.width
        lastHeight = newSize.height

        buffer.resize()
        if !screenStack.isEmpty {
            screenStack[screenStack.count - 1].onResize(width: newSize.width, height: newSize.height)
        }
        renderCurrentScreen()
    }

    // MARK: - Rendering

    private func renderCurrentScreen() {
        buffer.clear()
        guard !screenStack.isEmpty else { return }
        screenStack[screenStack.count - 1].render(into: &buffer)
        buffer.render()
    }

    // MARK: - Cleanup

    private func cleanup() {
        Terminal.showCursor()
        Terminal.alternateScreen(enable: false)
        Terminal.restoreMode()
    }

    // MARK: - Signal Handling

    private func installSignalHandlers() {
        // SIGINT: write raw escape sequences and _exit.
        // Uses only async-signal-safe operations (write, tcgetattr, tcsetattr, _exit).
        signal(SIGINT) { _ in
            // Static buffer — no heap allocation
            // ESC[?25h = show cursor, ESC[?1049l = exit alt screen
            var buf: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
                (0x1B, 0x5B, 0x3F, 0x32, 0x35, 0x68,       // \e[?25h
                 0x1B, 0x5B, 0x3F, 0x31, 0x30, 0x34, 0x39, 0x6C, // \e[?1049l
                 0x1B, 0x5B, 0x30, 0x6D)                    // \e[0m (reset)
            withUnsafePointer(to: &buf) { ptr in
                _ = write(STDOUT_FILENO, ptr, 18)
            }

            // Restore terminal mode
            var tattr = termios()
            tcgetattr(STDIN_FILENO, &tattr)
            tattr.c_lflag |= tcflag_t(ECHO | ICANON)
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &tattr)

            _exit(0)
        }

        // SIGWINCH: just set a flag (async-signal-safe), handled in event loop
        signal(SIGWINCH) { _ in
            resizeRequested = 1
        }
    }
}

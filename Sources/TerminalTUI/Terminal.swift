// Terminal.swift — Low-level terminal control
//
// Handles raw mode, terminal size detection, cursor visibility, and cleanup.
// Cross-platform: macOS, Linux, WSL. Windows falls back gracefully.
//
// Usage:
//   Terminal.enableRawMode()
//   defer { Terminal.restoreMode() }
//   let size = Terminal.size()

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation

public enum Terminal {

    // MARK: - Raw Mode

    /// Saved terminal attributes, restored on exit
    private static var savedTermios: termios?

    /// Switch the terminal into raw mode (no echo, no line buffering).
    /// Always pair with `restoreMode()` — ideally via `defer`.
    public static func enableRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        savedTermios = raw

        // Disable echo, canonical mode, and signal generation
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG)

        // Set VMIN=0 (don't block), VTIME=1 (100ms timeout) for non-blocking reads.
        // c_cc is a tuple in Swift; indices differ per platform, so we use withUnsafeMutablePointer.
        withUnsafeMutablePointer(to: &raw.c_cc) { ptr in
            let cc = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: cc_t.self)
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = 1
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    /// Restore the terminal to its original state.
    public static func restoreMode() {
        guard var saved = savedTermios else { return }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved)
        // Re-show cursor and clear any leftover styling
        write(ANSI.showCursor + ANSI.reset)
    }

    // MARK: - Terminal Size

    /// Returns (columns, rows) of the current terminal window
    public static func size() -> (width: Int, height: Int) {
        var ws = winsize()
        let request = UInt(TIOCGWINSZ)
        if ioctl(STDOUT_FILENO, request, &ws) == 0,
           ws.ws_col > 0, ws.ws_row > 0 {
            return (Int(ws.ws_col), Int(ws.ws_row))
        }
        // Fallback for environments that don't support TIOCGWINSZ
        return (80, 24)
    }

    // MARK: - Cursor

    public static func hideCursor() {
        write(ANSI.hideCursor)
    }

    public static func showCursor() {
        write(ANSI.showCursor)
    }

    public static func moveCursor(row: Int, col: Int) {
        write(ANSI.moveTo(row: row, col: col))
    }

    // MARK: - Screen

    public static func clearScreen() {
        write(ANSI.clearScreen + ANSI.moveTo(row: 0, col: 0))
    }

    public static func alternateScreen(enable: Bool) {
        write(enable ? ANSI.enterAltScreen : ANSI.exitAltScreen)
    }

    // MARK: - Output

    /// Write a string directly to stdout (unbuffered)
    public static func write(_ string: String) {
        let data = Array(string.utf8)
        _ = Foundation.write(STDOUT_FILENO, data, data.count)
    }

    /// Flush stdout
    public static func flush() {
        fflush(stdout)
    }
}

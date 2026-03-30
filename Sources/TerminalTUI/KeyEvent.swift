// KeyEvent.swift — Cross-platform key reading and event types
//
// Reads raw bytes from stdin and parses them into structured KeyEvent values.
// Handles arrow keys, special keys, and multi-byte escape sequences.
//
// Usage:
//   if let key = KeyReader.read() {
//       switch key {
//       case .char("q"): quit()
//       case .arrow(.up): moveUp()
//       case .enter: confirm()
//       default: break
//       }
//   }

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation

// MARK: - Key Event Types

/// Represents a single keypress from the terminal
public enum KeyEvent: Equatable, Sendable {
    case char(Character)       // Printable character (including UTF-8)
    case arrow(ArrowKey)       // Arrow keys
    case enter                 // Enter/Return
    case escape                // Bare Escape
    case backspace             // Backspace/Delete
    case delete                // Forward delete
    case tab                   // Tab
    case shiftTab              // Shift+Tab (backtab)
    case home                  // Home key
    case end                   // End key
    case pageUp                // Page Up
    case pageDown              // Page Down
    case ctrlC                 // Ctrl+C (interrupt)
    case ctrlD                 // Ctrl+D (EOF)
    case ctrlR                 // Ctrl+R (refresh)
    case ctrlF                 // Ctrl+F (find/search)
    case ctrlK                 // Ctrl+K (kill)
    case unknown               // Unrecognized sequence
}

/// Arrow key directions
public enum ArrowKey: Equatable, Sendable {
    case up, down, left, right
}

// MARK: - Key Reader

public enum KeyReader {

    /// Read a single key event from stdin. Returns nil on timeout/EOF.
    /// Must be called after `Terminal.enableRawMode()`.
    public static func read() -> KeyEvent? {
        guard let first = readByte() else { return nil }

        switch first {
        // Escape sequence
        case 0x1B:
            return parseEscapeSequence()

        // Control characters
        case 0x03: return .ctrlC
        case 0x04: return .ctrlD
        case 0x06: return .ctrlF
        case 0x0B: return .ctrlK
        case 0x09: return .tab
        case 0x0D, 0x0A: return .enter
        case 0x12: return .ctrlR
        case 0x7F: return .backspace

        // UTF-8 multi-byte sequences (2-4 bytes)
        case 0xC0...0xDF: return readUTF8(first, totalBytes: 2)
        case 0xE0...0xEF: return readUTF8(first, totalBytes: 3)
        case 0xF0...0xF7: return readUTF8(first, totalBytes: 4)

        // Printable ASCII
        default:
            if first >= 0x20, first < 0x7F,
               let scalar = Unicode.Scalar(UInt32(first)) {
                return .char(Character(scalar))
            }
            return .unknown
        }
    }

    /// Blocking read with a timeout (seconds). Returns nil if no input within timeout.
    public static func read(timeout: TimeInterval) -> KeyEvent? {
        var pollFd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ms = Int32(timeout * 1000)
        let ready = poll(&pollFd, 1, ms)
        guard ready > 0 else { return nil }
        return read()
    }

    // MARK: - Internal Parsing

    private static func readByte() -> UInt8? {
        var buf: UInt8 = 0
        let n = Foundation.read(STDIN_FILENO, &buf, 1)
        return n == 1 ? buf : nil
    }

    /// Try to read a byte without blocking (peek-style).
    /// Uses 50ms timeout — enough for multi-byte escape sequences.
    private static func peekByte() -> UInt8? {
        var pollFd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pollFd, 1, 50)
        guard ready > 0 else { return nil }
        return readByte()
    }

    /// Read remaining bytes of a UTF-8 multi-byte character
    private static func readUTF8(_ first: UInt8, totalBytes: Int) -> KeyEvent {
        var bytes = [first]
        for _ in 1..<totalBytes {
            guard let next = peekByte() else { return .unknown }
            bytes.append(next)
        }
        if let str = String(bytes: bytes, encoding: .utf8), let char = str.first {
            return .char(char)
        }
        return .unknown
    }

    /// Drain remaining bytes of an unrecognized escape sequence to prevent
    /// them from being misinterpreted as subsequent keypresses.
    private static func drainSequence() {
        while peekByte() != nil { /* consume */ }
    }

    /// Parse an escape sequence after reading 0x1B
    private static func parseEscapeSequence() -> KeyEvent {
        guard let second = peekByte() else { return .escape }

        switch second {
        // CSI sequences: ESC [ ...
        case 0x5B: // '['
            return parseCSI()

        // SS3 sequences: ESC O ... (some terminals use this for arrows / F1-F4)
        case 0x4F: // 'O'
            guard let third = peekByte() else { return .escape }
            switch third {
            case 0x41: return .arrow(.up)
            case 0x42: return .arrow(.down)
            case 0x43: return .arrow(.right)
            case 0x44: return .arrow(.left)
            default:
                drainSequence()
                return .unknown
            }

        default:
            return .escape
        }
    }

    /// Parse a CSI (Control Sequence Introducer) sequence after ESC [
    /// Handles: arrows, Home/End, Delete, PageUp/Down, and extended sequences.
    private static func parseCSI() -> KeyEvent {
        // Collect numeric parameter bytes and the final byte
        var params: [UInt8] = []

        while let byte = peekByte() {
            switch byte {
            // Final bytes — these terminate the sequence
            case 0x41: return .arrow(.up)       // A
            case 0x42: return .arrow(.down)     // B
            case 0x43: return .arrow(.right)    // C
            case 0x44: return .arrow(.left)     // D
            case 0x48: return .home             // H
            case 0x46: return .end              // F
            case 0x5A: return .shiftTab         // Z

            // Tilde-terminated sequences: ESC [ <digits> ~
            case 0x7E: // '~'
                return parseTildeSequence(params)

            // Parameter and intermediate bytes — collect them
            case 0x30...0x3F:  // digits, semicolons, etc.
                params.append(byte)

            default:
                // Unknown final byte — drain and discard
                drainSequence()
                return .unknown
            }
        }

        return .escape
    }

    /// Decode a ~-terminated sequence like ESC[3~, ESC[15~, ESC[1;5A
    private static func parseTildeSequence(_ params: [UInt8]) -> KeyEvent {
        let paramStr = String(bytes: params, encoding: .ascii) ?? ""
        // Take the first numeric segment (before any semicolons)
        let code = paramStr.split(separator: ";").first.flatMap { Int($0) } ?? 0

        switch code {
        case 1:  return .home     // ESC[1~
        case 2:  return .unknown  // Insert — not mapped
        case 3:  return .delete   // ESC[3~
        case 4:  return .end      // ESC[4~
        case 5:  return .pageUp   // ESC[5~
        case 6:  return .pageDown // ESC[6~
        case 7:  return .home     // ESC[7~ (alternate)
        case 8:  return .end      // ESC[8~ (alternate)
        default: return .unknown
        }
    }
}

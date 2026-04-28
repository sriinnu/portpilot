import Foundation

// MARK: - Alert State

/// Tri-state signal I propagate across every surface so the menubar pulse,
/// the main status bar, and the inspector all paint from one source of truth.
///
/// I keep the enum deliberately tiny — three cases, one computed convenience —
/// so adding new tones stays a focused decision rather than a sprawling refactor.
enum AlertState {
    case normal, warning, critical

    /// `true` when the state is anything louder than `.normal`, so call sites
    /// can branch on "should I draw chrome for this" without spelling out cases.
    var isAlert: Bool { self != .normal }
}

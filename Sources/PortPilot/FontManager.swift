import Foundation
import AppKit
import CoreText

// MARK: - Font Manager
/// Manages font discovery from the system and custom fonts directories.
/// Primary: Fonts/ folder in the app's project directory (next to Sources/).
/// Secondary: ~/Library/Application Support/PortPilot/Fonts/ for user-installed fonts.
/// Drop .ttf/.otf files into either folder and reload.
class FontManager: ObservableObject {
    static let shared = FontManager()

    /// Fonts loaded from custom fonts directories
    @Published private(set) var customFontFamilies: [String] = []

    /// All available font families (curated + custom)
    @Published private(set) var availableFamilies: [String] = []

    /// All available monospaced font families
    @Published private(set) var monospacedFamilies: [String] = []

    /// Primary fonts folder (project-local Fonts/ directory)
    let projectFontsURL: URL

    /// Secondary fonts folder (Application Support)
    let appSupportFontsURL: URL

    /// All font directories to scan
    var allFontFolders: [URL] {
        [projectFontsURL, appSupportFontsURL]
    }

    /// Curated list of recommended UI fonts (detected from system)
    private let curatedUIFonts = [
        "System Default",
        ".AppleSystemUIFont",
        "SF Pro",
        "SF Pro Display",
        "SF Pro Rounded",
        "SF Pro Text",
        "Helvetica Neue",
        "Avenir Next",
        "Inter",
        "IBM Plex Sans",
    ]

    /// Curated list of recommended monospaced fonts
    private let curatedMonoFonts = [
        "System Monospaced",
        "SF Mono",
        "Fira Code",
        "JetBrains Mono",
        "Source Code Pro",
        "Menlo",
        "Monaco",
        "Cascadia Code",
        "IBM Plex Mono",
        "Inconsolata",
    ]

    private init() {
        // Project-local Fonts/ folder: resolve from the executable's location
        // During development, the executable is in .build/debug/ — walk up to project root
        // For a distributed .app, look next to the .app bundle
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let projectFonts = FontManager.resolveProjectFontsFolder(from: execURL)
        self.projectFontsURL = projectFonts

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appSupportFontsURL = appSupport.appendingPathComponent("PortPilot/Fonts", isDirectory: true)

        ensureFontsDirectories()
        loadCustomFonts()
        refreshAvailableFamilies()
    }

    // MARK: - Public API

    /// Reload fonts from all custom directories
    func reload() {
        // Ensure @Published property updates happen on the main thread
        if Thread.isMainThread {
            loadCustomFonts()
            refreshAvailableFamilies()
        } else {
            DispatchQueue.main.sync {
                loadCustomFonts()
                refreshAvailableFamilies()
            }
        }
    }

    /// Open the primary (project) fonts folder in Finder
    func revealFontsFolder() {
        NSWorkspace.shared.open(projectFontsURL)
    }

    /// Open the secondary (App Support) fonts folder in Finder
    func revealAppSupportFontsFolder() {
        NSWorkspace.shared.open(appSupportFontsURL)
    }

    /// Get an NSFont for the selected UI font family
    func uiFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let family = AppSettings.shared.selectedFont
        if family == "System Default" || family == ".AppleSystemUIFont" {
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
        if let font = NSFont(name: postscriptName(family: family, weight: weight), size: size) {
            return font
        }
        if let font = NSFont(name: family, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Get an NSFont for the selected monospaced font family
    func monoFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let family = AppSettings.shared.selectedMonoFont
        if family == "System Monospaced" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
        if let font = NSFont(name: postscriptName(family: family, weight: weight), size: size) {
            return font
        }
        if let font = NSFont(name: family, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Check if a font family is actually available on the system
    func isFamilyAvailable(_ family: String) -> Bool {
        if family == "System Default" || family == ".AppleSystemUIFont" || family == "System Monospaced" {
            return true
        }
        return NSFontManager.shared.availableFontFamilies.contains(family)
    }

    // MARK: - Private

    /// Walk up from the executable to find the project root containing Package.swift
    private static func resolveProjectFontsFolder(from execURL: URL) -> URL {
        var dir = execURL.deletingLastPathComponent()
        // Walk up max 10 levels looking for Package.swift (project root indicator)
        for _ in 0..<10 {
            let packageSwift = dir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwift.path) {
                return dir.appendingPathComponent("Fonts", isDirectory: true)
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }
            dir = parent
        }
        // Fallback: for .app bundles, look next to the bundle
        if let bundlePath = Bundle.main.bundlePath as String? {
            let bundleDir = URL(fileURLWithPath: bundlePath).deletingLastPathComponent()
            return bundleDir.appendingPathComponent("Fonts", isDirectory: true)
        }
        // Last resort: Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("PortPilot/Fonts", isDirectory: true)
    }

    private func ensureFontsDirectories() {
        let fm = FileManager.default
        for folder in allFontFolders {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    private func loadCustomFonts() {
        let fm = FileManager.default
        let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "woff"]
        var families = Set<String>()

        for folder in allFontFolders {
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
                continue
            }

            for file in files where fontExtensions.contains(file.pathExtension.lowercased()) {
                var errorRef: Unmanaged<CFError>?
                let registered = CTFontManagerRegisterFontsForURL(file as CFURL, .process, &errorRef)

                // Properly release any CFError to avoid memory leak
                if let cfError = errorRef?.takeRetainedValue() {
                    let nsError = cfError as Error
                    // Font already registered is not a real error — only log unexpected failures
                    if !nsError.localizedDescription.contains("already registered") {
                        print("[FontManager] Failed to register \(file.lastPathComponent): \(nsError.localizedDescription)")
                    }
                }

                // Extract family names from the font file (works even if already registered)
                if registered || errorRef != nil {
                    if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] {
                        for desc in descriptors {
                            if let familyName = CTFontDescriptorCopyAttribute(desc, kCTFontFamilyNameAttribute) as? String {
                                families.insert(familyName)
                            }
                        }
                    }
                }
            }
        }

        customFontFamilies = families.sorted()
    }

    private func refreshAvailableFamilies() {
        // UI fonts: curated (only if available) + custom
        var uiFonts = curatedUIFonts.filter { isFamilyAvailable($0) }
        for family in customFontFamilies where !uiFonts.contains(family) {
            uiFonts.append(family)
        }
        availableFamilies = uiFonts

        // Mono fonts: curated (only if available) + custom monospaced
        var monoFonts = curatedMonoFonts.filter { isFamilyAvailable($0) }
        for family in customFontFamilies {
            if !monoFonts.contains(family) {
                if let font = NSFont(name: family, size: 12),
                   font.isFixedPitch {
                    monoFonts.append(family)
                }
            }
        }
        monospacedFamilies = monoFonts
    }

    /// Attempt to find the PostScript name for a family + weight combo
    private func postscriptName(family: String, weight: NSFont.Weight) -> String {
        let weightSuffix: String
        switch weight {
        case .ultraLight: weightSuffix = "UltraLight"
        case .thin: weightSuffix = "Thin"
        case .light: weightSuffix = "Light"
        case .regular: weightSuffix = "Regular"
        case .medium: weightSuffix = "Medium"
        case .semibold: weightSuffix = "Semibold"
        case .bold: weightSuffix = "Bold"
        case .heavy: weightSuffix = "Heavy"
        case .black: weightSuffix = "Black"
        default: weightSuffix = "Regular"
        }

        let candidates = [
            "\(family)-\(weightSuffix)",
            family.replacingOccurrences(of: " ", with: "") + "-" + weightSuffix,
            family.replacingOccurrences(of: " ", with: ""),
        ]

        for name in candidates {
            if NSFont(name: name, size: 12) != nil {
                return name
            }
        }

        return family
    }
}

// MARK: - SwiftUI Font Helpers
import SwiftUI

extension AppSettings {
    /// Returns a SwiftUI Font for the selected UI font family
    func appFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if selectedFont == "System Default" || selectedFont == ".AppleSystemUIFont" {
            return .system(size: size, weight: weight)
        }
        return .custom(selectedFont, size: size).weight(weight)
    }

    /// Returns a SwiftUI Font for the selected monospaced font family
    func appMonoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if selectedMonoFont == "System Monospaced" {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(selectedMonoFont, size: size).weight(weight)
    }
}

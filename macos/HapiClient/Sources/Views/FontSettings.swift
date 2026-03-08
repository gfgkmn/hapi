import SwiftUI

final class FontSettings: ObservableObject {
    static let shared = FontSettings()

    @AppStorage("fontSize") var fontSize: Double = 14
    @AppStorage("codeFontSize") var codeFontSize: Double = 13
    @AppStorage("fontFamily") var fontFamily: String = "FZJuZhenXinFangK"
    @AppStorage("codeFontFamily") var codeFontFamily: String = "Menlo"

    /// Body text font
    var bodyFont: Font {
        if fontFamily == "System" {
            return .system(size: fontSize)
        }
        return .custom(fontFamily, size: fontSize)
    }

    /// Monospaced code font
    var codeFont: Font {
        .custom(codeFontFamily, size: codeFontSize)
    }

    /// Caption-sized code font (tool results, output blocks)
    var smallCodeFont: Font {
        .custom(codeFontFamily, size: codeFontSize - 2)
    }

    static let availableFontFamilies: [String] = {
        var families = ["System"]
        families.append(contentsOf: NSFontManager.shared.availableFontFamilies.sorted())
        return families
    }()

    static let availableMonoFamilies: [String] = {
        let manager = NSFontManager.shared
        let mono = manager.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 13) else { return false }
            return font.isFixedPitch || family.lowercased().contains("mono") ||
                   family.lowercased().contains("code") || family.lowercased().contains("menlo") ||
                   family.lowercased().contains("courier") || family.lowercased().contains("consolas")
        }
        return mono.sorted()
    }()
}

// MARK: - Environment Key

private struct FontSettingsKey: EnvironmentKey {
    static let defaultValue = FontSettings.shared
}

extension EnvironmentValues {
    var fontSettings: FontSettings {
        get { self[FontSettingsKey.self] }
        set { self[FontSettingsKey.self] = newValue }
    }
}

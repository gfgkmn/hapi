import SwiftUI
import UIKit

final class FontSettings: ObservableObject {
    static let shared = FontSettings()

    static let bundledFontName = "FZJuZhenXinFangK"

    @AppStorage("fontSize") var fontSize: Double = 16
    @AppStorage("codeFontSize") var codeFontSize: Double = 14
    @AppStorage("fontFamily") var fontFamily: String = FontSettings.bundledFontName
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
        .custom(codeFontFamily, size: max(codeFontSize - 2, 10))
    }

    static let availableFontFamilies: [String] = {
        var families = ["System", bundledFontName]
        families.append(contentsOf: UIFont.familyNames.sorted())
        return families
    }()

    static let availableMonoFamilies: [String] = {
        let allFamilies = UIFont.familyNames
        let mono = allFamilies.filter { family in
            let lower = family.lowercased()
            return lower.contains("mono") || lower.contains("courier") ||
                   lower.contains("menlo") || lower.contains("code") ||
                   lower.contains("consolas")
        }
        return mono.sorted()
    }()
}

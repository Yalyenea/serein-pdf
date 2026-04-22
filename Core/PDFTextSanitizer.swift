import Foundation

enum PDFTextSanitizer {
    static func sanitize(_ text: String) -> String {
        var cleanedScalars: [UnicodeScalar] = []

        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                cleanedScalars.append(" ")
                continue
            }

            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .unassigned:
                continue
            default:
                cleanedScalars.append(scalar)
            }
        }

        return String(String.UnicodeScalarView(cleanedScalars))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

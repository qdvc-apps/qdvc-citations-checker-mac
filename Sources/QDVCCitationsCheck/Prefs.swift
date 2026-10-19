import CitationsCore
import Foundation

/// App preferences, in the standard defaults domain
/// (`defaults read org.qdvc.citationscheck.mac`). The pasted manuscript is
/// never stored; only these settings are.
enum Prefs {
    private static var defaults: UserDefaults { .standard }

    /// The citation style, as JSON (missing keys fall back to the defaults).
    static var style: CitationStyle {
        get {
            guard let data = defaults.data(forKey: "citationStyle"),
                  let style = try? JSONDecoder().decode(CitationStyle.self, from: data) else { return .standard }
            return style
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "citationStyle")
            }
        }
    }

    static var inspectorShown: Bool {
        get { defaults.object(forKey: "inspectorShown") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "inspectorShown") }
    }

    static var underlineIssues: Bool {
        get { defaults.object(forKey: "underlineIssues") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "underlineIssues") }
    }

    static let defaultFontSize: Double = 14
    static let fontSizeRange: ClosedRange<Double> = 10...32

    /// The manuscript's text size, in points.
    static var fontSize: Double {
        get {
            let v = defaults.object(forKey: "fontSize") as? Double ?? defaultFontSize
            return min(max(v, fontSizeRange.lowerBound), fontSizeRange.upperBound)
        }
        set { defaults.set(newValue, forKey: "fontSize") }
    }
}

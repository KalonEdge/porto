import Foundation

/// Number and time formats shared by the app and the terminal UI.
enum Format {
    /// Binary units, matching Activity Monitor and "16 GB" on a 16 GB Mac.
    static let megabyte: Double = 1_048_576
    static let gigabyte: Double = 1_073_741_824

    /// "1.21 GB" or "184 MB".
    static func bytes(_ value: UInt64) -> (number: String, unit: String) {
        let mb = Double(value) / megabyte
        if mb >= 1024 { return (String(format: "%.2f", mb / 1024), "GB") }
        return (String(format: "%.0f", mb), "MB")
    }

    static func bytesString(_ value: UInt64) -> String {
        let parts = bytes(value)
        return "\(parts.number) \(parts.unit)"
    }

    /// Compact totals for headers: "4.9 GB", "16 GB", "612 MB".
    static func total(_ value: UInt64) -> (number: String, unit: String) {
        let mb = Double(value) / megabyte
        guard mb >= 1024 else { return (String(format: "%.0f", mb), "MB") }
        let text = String(format: "%.1f", mb / 1024)
        return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text, "GB")
    }

    static func totalString(_ value: UInt64) -> String {
        let parts = total(value)
        return "\(parts.number) \(parts.unit)"
    }

    /// "<1m", "12m", "3h 12m", "2d".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        guard hours < 24 else { return "\(hours / 24)d" }
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "1m", "3h", "2d": one unit, for row captions.
    static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)h" : "\(hours / 24)d"
    }

    /// Whole numbers from 10% up and one decimal below, so an idle but living
    /// server reads "0.3%" rather than a flat "0%".
    static func percent(_ value: Double) -> String {
        if value <= 0 { return "0%" }
        if value < 0.1 { return "<0.1%" }
        if value < 10 { return String(format: "%.1f%%", value) }
        return "\(Int(value.rounded()))%"
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'Today' h:mm a" : "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    /// "2" or "1.5", for thresholds in GB.
    static func trim(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

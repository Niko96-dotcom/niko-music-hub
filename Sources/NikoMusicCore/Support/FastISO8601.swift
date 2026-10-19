import Foundation

/// Parses the one date spelling the app writes (`2026-09-04T10:11:12Z`: UTC, whole seconds) without
/// `ISO8601DateFormatter` or the `.iso8601` JSON strategy, which build calendars and time zones for
/// every value. A 10,000-song snapshot holds tens of thousands of dates and decoding them was a third
/// of the load. Anything else, including fractional seconds, offsets, leap seconds and years outside
/// 1900...2199 (where the Gregorian calendar's historical cutover could matter), returns `nil` so the
/// caller falls back to the Foundation parser and keeps its exact behavior.
enum FastISO8601 {
    static func date(from string: String) -> Date? {
        var string = string
        return string.withUTF8 { date(fromUTF8: $0) }
    }

    /// The fast parse, then `formatter` for any other spelling: the answer `formatter.date(from:)` gives.
    static func date(from string: String, fallback formatter: ISO8601DateFormatter) -> Date? {
        date(from: string) ?? formatter.date(from: string)
    }

    static func date(fromUTF8 bytes: UnsafeBufferPointer<UInt8>) -> Date? {
        guard bytes.count == 20,
              bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"),
              bytes[10] == UInt8(ascii: "T"),
              bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":"),
              bytes[19] == UInt8(ascii: "Z"),
              let year = number(bytes, 0, 4), let month = number(bytes, 5, 2), let day = number(bytes, 8, 2),
              let hour = number(bytes, 11, 2), let minute = number(bytes, 14, 2), let second = number(bytes, 17, 2),
              (1900...2199).contains(year), (1...12).contains(month),
              hour < 24, minute < 60, second < 60,
              (1...daysInMonth(year: year, month: month)).contains(day) else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func number(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ count: Int) -> Int? {
        var value = 0
        for index in start..<(start + count) {
            let digit = Int(bytes[index]) - 48
            guard (0...9).contains(digit) else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's `days_from_civil`).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = shiftedYear / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

extension JSONDecoder.DateDecodingStrategy {
    /// Same dates as `.iso8601`, fast for the app's own spelling and identical (including errors) otherwise.
    static let fastISO8601: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        if let date = FastISO8601.date(from: text) { return date }
        return try FastISO8601Fallback.decode(text, codingPath: decoder.codingPath)
    }
}

private enum FastISO8601Fallback {
    /// Runs the value through a real `.iso8601` decoder so unusual spellings behave exactly as before.
    static func decode(_ text: String, codingPath: [CodingKey]) throws -> Date {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let quoted = try JSONEncoder().encode([text])
        do {
            return try decoder.decode([Date].self, from: quoted)[0]
        } catch let DecodingError.dataCorrupted(context) {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: context.debugDescription))
        }
    }
}

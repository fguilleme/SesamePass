import Foundation

/// ICAO TD3 access data. Only the access string is used to open the chip.
struct MRZAccess: Equatable, Sendable {
    let documentNumber: String
    let birthDate: String // YYMMDD
    let expiryDate: String // YYMMDD

    var key: String {
        let padded = documentNumber.padding(toLength: 9, withPad: "<", startingAt: 0)
        return padded + Self.checkDigit(padded) + birthDate + Self.checkDigit(birthDate) + expiryDate + Self.checkDigit(expiryDate)
    }

    init(documentNumber: String, birthDate: String, expiryDate: String) throws {
        let number = documentNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (1...9).contains(number.count), number.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else { throw MRZError.documentNumber }
        guard Self.isMRZDate(birthDate), Self.isMRZDate(expiryDate) else { throw MRZError.date }
        self.documentNumber = number
        self.birthDate = birthDate
        self.expiryDate = expiryDate
    }

    init(documentNumber: String, typedBirthDate: String, typedExpiryDate: String) throws {
        try self.init(documentNumber: documentNumber, birthDate: Self.parseTypedDate(typedBirthDate), expiryDate: Self.parseTypedDate(typedExpiryDate))
    }

    static func checkDigit(_ string: String) -> String {
        let weights = [7, 3, 1]
        let sum = string.utf8.enumerated().reduce(0) { result, item in
            let value: Int
            switch item.element {
            case 48...57: value = Int(item.element - 48)
            case 65...90: value = Int(item.element - 55)
            default: value = 0
            }
            return result + value * weights[item.offset % 3]
        }
        return String(sum % 10)
    }

    static func parseTD3(_ observations: [String]) throws -> MRZAccess {
        // OCR can split an MRZ line. Join only characters; never guess O/0 or I/1.
        let lines = observations.flatMap { $0.components(separatedBy: .newlines) }.map {
            $0.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "«", with: "<<")
        }
        for index in lines.indices {
            guard lines[index].hasPrefix("P") else { continue }
            var candidate = ""
            for part in lines[index...].prefix(6) {
                candidate += part
                if candidate.count == 88, let access = try? parseTD3(candidate) { return access }
                if candidate.count > 88 { break }
            }
        }
        throw MRZError.unreadable
    }

    static func parseTD3(_ text: String) throws -> MRZAccess {
        let normalized = text.uppercased().filter { !$0.isWhitespace }
        let bytes = Array(normalized.utf8)
        guard bytes.count == 88, bytes[0] == 80,
              bytes.allSatisfy({ $0 == 60 || (48...57).contains($0) || (65...90).contains($0) }) else { throw MRZError.unreadable }
        return try parseSecondLine(Array(bytes[44...]))
    }

    private static func parseSecondLine(_ second: [UInt8]) throws -> MRZAccess {
        func part(_ range: Range<Int>) -> String { String(decoding: second[range], as: UTF8.self) }
        func checked(_ range: Range<Int>, _ position: Int) -> Bool { checkDigit(part(range)) == part(position..<position+1) }
        let optionalBlank = part(28..<42).allSatisfy { $0 == "<" } && part(42..<43) == "<"
        guard (optionalBlank || checked(28..<42, 42)), checked(0..<9, 9), checked(13..<19, 19), checked(21..<27, 27),
              checkDigit(part(0..<10) + part(13..<20) + part(21..<43)) == part(43..<44) else { throw MRZError.checksum }
        let number = part(0..<9).replacingOccurrences(of: "<", with: "")
        return try MRZAccess(documentNumber: number, birthDate: part(13..<19), expiryDate: part(21..<27))
    }

    /// Camera prefill only. The chip MRZ still uses the strict TD3 parser.
    /// Names are not needed to open the chip; all second-line checks remain required.
    static func parseOCRLines(_ lines: [String]) throws -> MRZAccess {
        var matches: [MRZAccess] = []
        for line in lines.flatMap({ $0.components(separatedBy: .newlines) }) {
            let normalized = line.uppercased().filter { !$0.isWhitespace }
                .replacingOccurrences(of: "«", with: "<<")
                .replacingOccurrences(of: "‹", with: "<")
            var bytes = Array(normalized.utf8)
            if bytes.count == 88, bytes.first == 80 { bytes = Array(bytes.suffix(44)) }
            guard bytes.count == 44 else { continue }
            // Only numeric positions have an unambiguous letter-to-digit interpretation.
            // Never guess characters in the alphanumeric passport number.
            let numeric = [9] + Array(13...19) + Array(21...27) + [42, 43]
            for index in numeric {
                switch bytes[index] {
                case 79: bytes[index] = 48 // O -> 0
                case 73, 76: bytes[index] = 49 // I/l -> 1
                case 90: bytes[index] = 50 // Z -> 2
                case 83: bytes[index] = 53 // S -> 5
                case 66: bytes[index] = 56 // B -> 8
                default: break
                }
            }
            guard bytes.allSatisfy({ $0 == 60 || (48...57).contains($0) || (65...90).contains($0) }),
                  let access = try? parseSecondLine(bytes) else { continue }
            if !matches.contains(access) { matches.append(access) }
        }
        guard matches.count == 1, let result = matches.first else { throw MRZError.unreadable }
        return result
    }

    /// ICAO 9303 part 5: TD1, three lines of 30 characters.
    static func parseTD1(_ text: String) throws -> MRZAccess {
        let bytes = Array(text.uppercased().filter { !$0.isWhitespace }.utf8)
        guard bytes.count == 90,
              bytes.allSatisfy({ $0 == 60 || (48...57).contains($0) || (65...90).contains($0) }),
              [UInt8(73), 65, 67].contains(bytes[0]) else { throw MRZError.unreadable }
        return try td1Access(Array(bytes[0..<30]), Array(bytes[30..<60]))
    }

    private static func td1Access(_ first: [UInt8], _ second: [UInt8]) throws -> MRZAccess {
        func a(_ r: Range<Int>) -> String { String(decoding: first[r], as: UTF8.self) }
        func b(_ r: Range<Int>) -> String { String(decoding: second[r], as: UTF8.self) }
        // Extended document numbers are not supported; never silently truncate one.
        guard first[14] != 60 else { throw MRZError.documentNumber }
        guard checkDigit(a(5..<14)) == a(14..<15),
              checkDigit(b(0..<6)) == b(6..<7), checkDigit(b(8..<14)) == b(14..<15),
              checkDigit(a(5..<30) + b(0..<7) + b(8..<15) + b(18..<29)) == b(29..<30)
        else { throw MRZError.checksum }
        let number = a(5..<14)
        let trimmed = String(number.prefix { $0 != "<" })
        guard number == trimmed.padding(toLength: 9, withPad: "<", startingAt: 0) else { throw MRZError.documentNumber }
        return try MRZAccess(documentNumber: trimmed, birthDate: b(0..<6), expiryDate: b(8..<14))
    }

    static func parseTD1OCR(_ observations: [String]) throws -> MRZAccess {
        let lines = observations.flatMap { $0.components(separatedBy: .newlines) }.flatMap { text -> [[UInt8]] in
            let value = text.uppercased().filter { !$0.isWhitespace }
                .replacingOccurrences(of: "«", with: "<<").replacingOccurrences(of: "‹", with: "<")
            let bytes = Array(value.utf8)
            if bytes.count == 60 || bytes.count == 90 {
                return stride(from: 0, to: bytes.count, by: 30).map { Array(bytes[$0..<$0+30]) }
            }
            return [bytes]
        }.filter { $0.count == 30 && $0.allSatisfy { $0 == 60 || (48...57).contains($0) || (65...90).contains($0) } }
        func numeric(_ row: [UInt8], at positions: [Int]) -> [UInt8] {
            var value = row
            for i in positions {
                switch value[i] {
                case 79: value[i] = 48
                case 73, 76: value[i] = 49
                case 90: value[i] = 50
                case 83: value[i] = 53
                case 66: value[i] = 56
                default: break
                }
            }
            return value
        }
        var matches: [MRZAccess] = []
        // Bounded OCR alternatives; all four checks must validate each pair.
        for first in lines.prefix(256) where [UInt8(73), 65, 67].contains(first[0]) {
            for second in lines.prefix(256) {
                if let result = try? td1Access(numeric(first, at: [14]), numeric(second, at: Array(0...6) + Array(8...14) + [29])), !matches.contains(result) {
                    matches.append(result)
                }
            }
        }
        guard matches.count == 1, let result = matches.first else { throw MRZError.unreadable }
        return result
    }

    static func parseTypedDate(_ string: String) throws -> String {
        let bytes = Array(string.utf8)
        guard bytes.count == 10, bytes[2] == 47, bytes[5] == 47 else { throw MRZError.date }
        let parts = string.split(separator: "/")
        guard parts.count == 3, let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]),
              (1900...2199).contains(year), validDate(year: year, month: month, day: day),
              parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }) else { throw MRZError.date }
        return String(format: "%02d%02d%02d", year % 100, month, day)
    }

    /// Century is inferred for display only; BAC/PACE use the unchanged YYMMDD bytes.
    static func displayedDate(_ value: String, birth: Bool, now: Date = Date()) -> String {
        guard isMRZDate(value) else { return value }
        let year = Int(value.prefix(2))!
        let current = Calendar(identifier: .gregorian).component(.year, from: now)
        var fullYear = (current / 100) * 100 + year
        if birth, fullYear > current { fullYear -= 100 }
        if !birth, fullYear < current - 50 { fullYear += 100 }
        let month = String(value.dropFirst(2).prefix(2))
        let day = String(value.suffix(2))
        return "\(day)/\(month)/\(fullYear)"
    }

    private static func isMRZDate(_ value: String) -> Bool {
        guard value.utf8.count == 6, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let year = Int(value.prefix(2)), let month = Int(value.dropFirst(2).prefix(2)), let day = Int(value.suffix(2)) else { return false }
        return validDate(year: 2000 + year, month: month, day: day)
    }
    private static func validDate(year: Int, month: Int, day: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let result = calendar.dateComponents([.year, .month, .day], from: date)
        return result.year == year && result.month == month && result.day == day
    }
}

enum MRZError: Error, LocalizedError {
    case documentNumber, date, unreadable, checksum
    var errorDescription: String? {
        switch self {
        case .documentNumber: L10n.string("Saisissez le numéro du document, de 1 à 9 lettres ou chiffres, sans espaces.")
        case .date: L10n.string("Vérifiez les dates au format JJ/MM/AAAA.")
        case .unreadable: L10n.string("La zone de lecture automatique n’a pas pu être lue. Cadrez les deux lignes du passeport ou les trois lignes au verso de la carte, ou saisissez les informations.")
        case .checksum: L10n.string("La lecture de la page contient une erreur. Recommencez le scan ou saisissez les informations.")
        }
    }
}

import Foundation
import Testing
@testable import SesamePassSecurity

// Fixed-width ICAO sample constructed with padding to avoid copied filler errors.
private var cardMRZ: String {
    let first = "I<UTOD231458907".padding(toLength: 30, withPad: "<", startingAt: 0)
    let middle = "7408122F1204159UTO".padding(toLength: 29, withPad: "<", startingAt: 0)
    let composite = MRZAccess.checkDigit(String(first.dropFirst(5)) + String(middle.prefix(7)) + String(middle.dropFirst(8).prefix(7)) + String(middle.dropFirst(18)))
    return first + "\n" + middle + composite + "\n" + "ERIKSSON<<ANNA<MARIA".padding(toLength: 30, withPad: "<", startingAt: 0)
}
@Test func td1AccessKeyMatchesICAOSpecimen() throws {
    let access = try MRZAccess.parseTD1(cardMRZ)
    #expect(access.key == "D23145890774081221204159")
    #expect(cardMRZ.components(separatedBy: "\n")[1].last == "6")
}
@Test func td1CameraReadsFirstTwoLinesAndNumericConfusions() throws {
    let rows = cardMRZ.components(separatedBy: "\n")
    #expect(try MRZAccess.parseTD1OCR(Array(rows.prefix(2))) == MRZAccess.parseTD1(cardMRZ))
    #expect(try MRZAccess.parseTD1OCR([rows[0], rows[1].replacingOccurrences(of: "740812", with: "74O8I2")]) == MRZAccess.parseTD1(cardMRZ))
}
@Test func td1InvalidChecksAndUnsupportedFormatRejected() {
    #expect(throws: MRZError.self) { try MRZAccess.parseTD1(cardMRZ.replacingOccurrences(of: "7408122", with: "7408123")) }
    #expect(throws: MRZError.self) { try MRZAccess.parseTD1(cardMRZ.replacingOccurrences(of: "D231458907", with: "D23145890<")) }
    #expect(throws: MRZError.self) { try MRZAccess.parseTD3(cardMRZ) }
    #expect(throws: MRZError.self) { try MRZAccess.parseTD1(String(cardMRZ.dropLast())) }
}
@Test func td1CompositeAndAmbiguousOCRRejected() {
    var rows = cardMRZ.components(separatedBy: "\n")
    rows[1] = String(rows[1].dropLast()) + "0"
    #expect(throws: MRZError.self) { try MRZAccess.parseTD1(rows.joined(separator: "\n")) }
    #expect(throws: MRZError.self) { try MRZAccess.parseTD1OCR(rows) }
}
@Test func identityCardSurvivesArchiveAndOldPassportDefaults() throws {
    var record = PassportRecord(givenNames: "ANNA", surname: "SPECIMEN", documentNumber: "D23145890", nationality: "UTO", birthDate: "1974", expiryDate: "2012", mrz: cardMRZ, readAt: .distantPast, dataGroups: [:], checks: [])
    #expect(record.kind == .passport)
    record.documentKind = .identityCard
    let data = try ArchiveCipher.export(record, password: "synthetic-password-only")
    #expect(try ArchiveCipher.restore(data, password: "synthetic-password-only").kind == .identityCard)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
    json.removeValue(forKey: "documentKind")
    let old = try JSONDecoder().decode(PassportRecord.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.kind == .passport)
}

@Test func td1RejectsTwoDifferentValidDocumentsInOCR() {
    let rows = cardMRZ.components(separatedBy: "\n")
    var first = Array(rows[0])
    first[5] = "E"
    first[14] = Character(MRZAccess.checkDigit(String(first[5..<14])))
    let middle = Array(rows[1])
    let composite = MRZAccess.checkDigit(String(first[5..<30]) + String(middle[0..<7]) + String(middle[8..<15]) + String(middle[18..<29]))
    #expect(throws: MRZError.self) {
        try MRZAccess.parseTD1OCR(rows + [String(first), String(rows[1].dropLast()) + composite])
    }
}

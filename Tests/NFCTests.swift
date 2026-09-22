import Foundation
import Testing
@testable import SesamePassSecurity

private let td3 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO7408122F1204159ZE184226B<<<<<10"

@Test func td3OfficialSpecimenProducesAccessKey() throws {
    let access = try MRZAccess.parseTD3(td3)
    #expect(access.documentNumber == "L898902C3")
    #expect(access.birthDate == "740812")
    #expect(access.expiryDate == "120415")
    #expect(access.key == "L898902C3674081221204159")
}
@Test func manualInputProducesSameKeyAsMRZ() throws {
    let manual = try MRZAccess(documentNumber: "l898902c3", typedBirthDate: "12/08/1974", typedExpiryDate: "15/04/2012")
    #expect(try manual == MRZAccess.parseTD3(td3))
}
@Test func paddingUsesMRZFillerNotSpaces() throws {
    let access = try MRZAccess(documentNumber: "L898902C", birthDate: "690806", expiryDate: "940623")
    #expect(access.key == "L898902C<369080619406236")
}
@Test func changedDateCheckDigitRejected() {
    let modified = td3.replacingOccurrences(of: "7408122", with: "7408123")
    #expect(throws: MRZError.self) { try MRZAccess.parseTD3(modified) }
}
@Test func changedCompositeCheckDigitRejected() {
    #expect(throws: MRZError.self) { try MRZAccess.parseTD3(String(td3.dropLast()) + "1") }
}
@Test func partialMRZRejected() {
    #expect(throws: MRZError.self) { try MRZAccess.parseTD3(String(td3.dropLast(3))) }
}
@Test func ocrFindsMRZAmongUnrelatedText() throws {
    let lines = ["PASSPORT", "OTHER PRINTED TEXT"] + td3.components(separatedBy: "\n")
    #expect(try MRZAccess.parseTD3(lines) == MRZAccess.parseTD3(td3))
}
@Test func splitOCRLinesAreRejoinedWithoutGuessingCharacters() throws {
    let lines = td3.components(separatedBy: "\n")
    let fragmented = [lines[0], String(lines[1].prefix(20)), String(lines[1].dropFirst(20))]
    #expect(try MRZAccess.parseTD3(fragmented) == MRZAccess.parseTD3(td3))
    #expect(throws: MRZError.self) { try MRZAccess.parseTD3(td3.replacingOccurrences(of: "740812", with: "74O812")) }
}
@Test(arguments: ["31/02/2000", "29/02/1900", "1/01/2000", "01/13/2000", "00/01/2000", "01/01/abcd", "2000-01-01"])
func invalidTypedDatesRejected(_ input: String) {
    #expect(throws: MRZError.self) { try MRZAccess.parseTypedDate(input) }
}
@Test func leapDayAccepted() throws {
    #expect(try MRZAccess.parseTypedDate("29/02/2000") == "000229")
}
@Test(arguments: ["1234567890", "AB 12345", "A<123", "É1234567", "", "A😀123"])
func invalidDocumentNumbersRejected(_ input: String) {
    #expect(throws: MRZError.self) { try MRZAccess(documentNumber: input, birthDate: "900101", expiryDate: "300101") }
}
@Test func centuryFormattingDoesNotChangeAccessData() throws {
    let now = Date(timeIntervalSince1970: 1_789_000_000) // 2026
    #expect(MRZAccess.displayedDate("740812", birth: true, now: now) == "12/08/1974")
    #expect(MRZAccess.displayedDate("300415", birth: false, now: now) == "15/04/2030")
}
@Test func absentTrustListNeverReportedAsPassed() {
    let input = NFCVerification(pace: .passed, bac: .notPerformed, chip: .passed, active: .passed, signatureValid: true, hashesValid: true, hashedGroups: ["DG1", "DG2"], readGroups: ["DG1", "DG2"])
    #expect(input.checks.first { $0.name == "Confiance dans le pays émetteur" }?.result == .notPerformed)
    #expect(input.checks.first { $0.name == "Signature du SOD" }?.result == .passed)
}
@Test func partialHashCoverageIsNotSuccessfulIntegrity() {
    let input = NFCVerification(pace: .notPerformed, bac: .passed, chip: .notPerformed, active: .notPerformed, signatureValid: true, hashesValid: true, hashedGroups: ["DG1"], readGroups: ["DG1", "DG2"])
    #expect(input.checks.first { $0.name == "Intégrité des données lues" }?.result == .failed)
}
@Test func invalidSignatureDoesNotInheritSuccessfulHashResult() {
    let input = NFCVerification(pace: .notPerformed, bac: .passed, chip: .notPerformed, active: .notPerformed, signatureValid: false, hashesValid: true, hashedGroups: ["DG1", "DG2"], readGroups: ["DG1", "DG2"])
    #expect(input.checks.first { $0.name == "Signature du SOD" }?.result == .failed)
    #expect(input.checks.first { $0.name == "Authentification active" }?.result == .notPerformed)
}
@Test func oldRecordsWithoutNFCEvidenceStillDecode() throws {
    let record = PassportRecord(givenNames: "TEST", surname: "SPECIMEN", documentNumber: "FAKE", nationality: "UTO", birthDate: "2000", expiryDate: "2030", mrz: "", photograph: nil, readAt: .distantPast, dataGroups: [:], sod: nil, checks: [])
    let data = try JSONEncoder().encode(record)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "nfcEvidence")
    let decoded = try JSONDecoder().decode(PassportRecord.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.id == record.id)
    #expect(decoded.nfcEvidence == nil)
}
@Test func nfcEvidenceSurvivesEncryptedArchive() throws {
    var record = PassportRecord(givenNames: "TEST", surname: "SPECIMEN", documentNumber: "FAKE", nationality: "UTO", birthDate: "2000", expiryDate: "2030", mrz: "", photograph: nil, readAt: .distantPast, dataGroups: ["DG1": Data([1,2,3])], sod: Data([4,5,6]), checks: [])
    record.nfcEvidence = NFCEvidence(cardAccess: Data([1]), activeAuthenticationChallenge: Data([2]), activeAuthenticationSignature: Data([3]), hashes: ["DG1": .init(expected: "AA", computed: "AA", matches: true)], unreadGroups: ["DG3"])
    let archive = try ArchiveCipher.export(record, password: "synthetic-test-only-password")
    #expect(try ArchiveCipher.restore(archive, password: "synthetic-test-only-password") == record)
}

@Test func optionalFieldChecksumCannotBeHiddenByRecomputedComposite() {
    let lines = td3.components(separatedBy: "\n")
    var line = Array(lines[1])
    line[42] = "2"
    let compositeInput = String(line[0..<10]) + String(line[13..<20]) + String(line[21..<43])
    line[43] = Character(MRZAccess.checkDigit(compositeInput))
    #expect(throws: MRZError.self) { try MRZAccess.parseTD3(lines[0] + "\n" + String(line)) }
}

@Test func cameraCanReadAccessLineWithoutPerfectNameLine() throws {
    let line = td3.components(separatedBy: "\n")[1]
    #expect(try MRZAccess.parseOCRLines(["UNREADABLE NAME", line]) == MRZAccess.parseTD3(td3))
}
@Test func cameraCorrectsNumericGlyphsOnlyWithValidChecksums() throws {
    let line = td3.components(separatedBy: "\n")[1].replacingOccurrences(of: "740812", with: "74O8I2")
    #expect(try MRZAccess.parseOCRLines([line]) == MRZAccess.parseTD3(td3))
    #expect(throws: MRZError.self) { try MRZAccess.parseOCRLines([String(line.dropLast()) + "1"]) }
}
@Test func cameraRejectsIncompleteAndAmbiguousAccessLines() throws {
    let line = td3.components(separatedBy: "\n")[1]
    #expect(throws: MRZError.self) { try MRZAccess.parseOCRLines([String(line.dropLast())]) }
    var other = Array(line)
    other[0] = "M"
    other[9] = Character(MRZAccess.checkDigit(String(other[0..<9])))
    other[43] = Character(MRZAccess.checkDigit(String(other[0..<10]) + String(other[13..<20]) + String(other[21..<43])))
    #expect(throws: MRZError.self) { try MRZAccess.parseOCRLines([line, String(other)]) }
    #expect(try MRZAccess.parseOCRLines([line, line]) == MRZAccess.parseTD3(td3))
}
@Test func cameraDoesNotGuessPassportNumberCharacters() {
    let line = td3.components(separatedBy: "\n")[1].replacingOccurrences(of: "L898902C3", with: "L8989O2C3")
    #expect(throws: MRZError.self) { try MRZAccess.parseOCRLines([line]) }
}

@Test func cameraHandlesCombinedOrMultilineObservations() throws {
    #expect(try MRZAccess.parseOCRLines([td3]) == MRZAccess.parseTD3(td3))
    #expect(try MRZAccess.parseOCRLines([td3.replacingOccurrences(of: "\n", with: "")]) == MRZAccess.parseTD3(td3))
}

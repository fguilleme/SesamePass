// Sésame privacy patch: never log APDUs, MRZ, session keys or passport data.
// Upstream NFCPassportReader 2.3.3, MIT, copyright Andy Qua.
import OSLog
extension Logger {
    static let passportReader = Logger(.disabled)
    static let tagReader = Logger(.disabled)
    static let secureMessaging = Logger(.disabled)
    static let openSSL = Logger(.disabled)
    static let bac = Logger(.disabled)
    static let chipAuth = Logger(.disabled)
    static let pace = Logger(.disabled)
}

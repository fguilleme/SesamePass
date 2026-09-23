// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SesamePassSecurity",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SesamePassSecurity", targets: ["SesamePassSecurity"])],
    targets: [
        .target(name: "SesamePassSecurity", path: "SesamePass/Core", exclude: ["LocalStore.swift", "CloudBackup.swift", "PassportStore.swift"], sources: ["PassportRecord.swift", "Cryptography.swift", "MRZAccess.swift", "MRZRecognition.swift", "NFCEvidence.swift", "L10n.swift"]),
        .testTarget(name: "SesamePassSecurityTests", dependencies: ["SesamePassSecurity"], path: "Tests")
    ]
)

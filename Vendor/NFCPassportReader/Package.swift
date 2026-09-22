// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "NFCPassportReader",
    platforms: [.iOS(.v15)],
    products: [.library(name: "NFCPassportReader", targets: ["NFCPassportReader"])],
    dependencies: [.package(url: "https://github.com/krzyzanowskim/OpenSSL-Package.git", exact: "3.6.3000")],
    targets: [.target(name: "NFCPassportReader", dependencies: [.product(name: "OpenSSL", package: "OpenSSL-Package")], resources: [.copy("Resources/PrivacyInfo.xcprivacy")])]
)

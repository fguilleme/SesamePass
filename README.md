# SesamePass

**Français** · [English](#english)

SesamePass est une application iPhone en SwiftUI qui lit la puce NFC des passeports biométriques et des cartes d’identité électroniques compatibles. Les documents sont conservés dans une bibliothèque locale protégée et restent accessibles hors ligne.

L’application ne remplace pas un document d’identité ou de voyage officiel.

## Fonctionnalités

- Reconnaissance de la MRZ avec l’appareil photo ou saisie manuelle.
- Lecture NFC des passeports TD3 et des cartes d’identité électroniques TD1 compatibles.
- Accès à la puce par PACE, avec repli BAC lorsque le document l’exige.
- Lecture des groupes de données accessibles, de la photographie et du SOD.
- Vérification de la signature du SOD et de l’intégrité des groupes lus.
- Chip Authentication et Active Authentication lorsqu’elles sont disponibles.
- Stockage local chiffré et protégé par iOS.
- Verrouillage facultatif par Face ID, Touch ID ou code de l’appareil.
- Export en PDF lisible ou en archive protégée par mot de passe.
- Interface disponible en français et en anglais.
- Fonctionnement hors ligne, sans publicité, analytics ni serveur tiers.

## Utilisation

1. Toucher **Lire un document**.
2. Choisir le passeport ou la carte d’identité.
3. Scanner la MRZ avec l’appareil photo ou saisir les informations demandées.
4. Vérifier le numéro du document et les dates de naissance et d’expiration.
5. Toucher **Lire la puce NFC**.
6. Poser le haut de l’iPhone contre le document et le maintenir immobile jusqu’à la fin de la lecture.

Le document est enregistré localement dès que la lecture aboutit. Son détail présente les informations lues et le résultat de chaque vérification cryptographique.

## Compatibilité

La lecture NFC nécessite un iPhone compatible et un document électronique muni d’une puce sans contact. Son emplacement varie selon le document ; il peut être nécessaire d’essayer la couverture et la page d’identité.

Le simulateur et l’iPad permettent de parcourir l’interface et d’importer une archive, mais ne peuvent pas effectuer une lecture NFC. La saisie actuelle ne prend pas en charge les numéros étendus de plus de neuf caractères ni les documents TD2.

## Confidentialité et stockage

Un `PassportRecord` peut contenir l’identité, la photographie, la MRZ, les groupes de données lus, le SOD, la date de lecture NFC et les résultats techniques des contrôles.

- Les données locales utilisent AES-256-GCM, la protection complète des fichiers iOS et une clé conservée dans le Trousseau.
- Le verrouillage de SesamePass est désactivé par défaut et peut être activé dans les réglages.
- Les scans Vision et les échanges NFC sont traités localement.
- Aucun serveur tiers, outil publicitaire, analytics ou tracking n’est intégré.
- Les exports PDF portent la mention « Copie numérique — ne remplace pas un document de voyage. »
- Les archives SesamePass sont protégées par un mot de passe et peuvent être réimportées sans compte Apple.

La sauvegarde iCloud, lorsqu’elle est activée et configurée, utilise la base privée CloudKit. Les données sont chiffrées avant leur envoi ; CloudKit reçoit un `CKAsset` contenant le payload chiffré. La clé de sauvegarde est conservée dans le Trousseau iCloud synchronisable. L’application reste utilisable lorsque cette option est désactivée ou hors ligne.

## Portée des vérifications

SesamePass vérifie la signature du SOD et compare les empreintes des groupes effectivement lus. **Aucune liste de certificats nationaux de confiance n’est embarquée.** L’application ne peut donc pas certifier à elle seule la confiance dans le pays émetteur ; ce contrôle apparaît comme « Non effectuée ».

## Ouvrir et compiler

Prérequis : Xcode, iOS 18 ou version ultérieure et Swift 6.

1. Ouvrir `SesamePass.xcodeproj`.
2. Sélectionner le scheme **SesamePass**.
3. Choisir une équipe Apple Developer dans **Signing & Capabilities**.
4. Vérifier que la capability **Near Field Communication Tag Reading** est autorisée pour l’App ID et présente dans le profil de signature.
5. Compiler sur un iPhone réel pour tester la lecture NFC.

Les entitlements ISO 7816 sont déjà déclarés. Xcode résout OpenSSL-Package lors de la première compilation.

```sh
xcodebuild -project SesamePass.xcodeproj \
  -scheme SesamePass \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build

swift test
```

Le lecteur repose sur une copie locale de NFCPassportReader 2.3.3 sous licence MIT, avec ses journaux désactivés et des corrections ciblées. OpenSSL-Package est fixé à la version 3.6.3000. Voir [les modifications du lecteur](Vendor/NFCPassportReader/SESAME-PATCHES.md).

## Documentation

- [Lecture NFC et procédure de test](Documentation/NFC.md)
- [Sécurité et récupération des clés](Documentation/SECURITY.md)
- [Configuration iCloud](Documentation/ICLOUD.md)
- [Validation](Documentation/VALIDATION.md)

---

## English

[Français](#sesamepass) · **English**

SesamePass is a SwiftUI iPhone app that reads the NFC chip in compatible biometric passports and electronic identity cards. Documents are kept in a protected local library and remain available offline.

The app does not replace an official identity or travel document.

## Features

- MRZ recognition with the camera or manual entry.
- NFC reading for compatible TD3 passports and TD1 electronic identity cards.
- PACE chip access, with BAC fallback when required by the document.
- Reading of accessible data groups, the portrait and the SOD.
- SOD signature and data group integrity verification.
- Chip Authentication and Active Authentication when available.
- Encrypted local storage protected by iOS.
- Optional locking with Face ID, Touch ID or the device passcode.
- Export as a readable PDF or a password-protected archive.
- French and English interface.
- Offline operation with no advertising, analytics or third-party server.

## How to use

1. Tap **Read a document**.
2. Choose a passport or identity card.
3. Scan the MRZ with the camera or enter the requested information.
4. Check the document number, date of birth and expiry date.
5. Tap **Read NFC chip**.
6. Hold the top of the iPhone against the document until reading is complete.

The document is stored locally as soon as the reading succeeds. Its detail view shows the information read from the chip and the result of each cryptographic check.

## Compatibility

NFC reading requires a compatible iPhone and an electronic document with a contactless chip. Chip placement varies; you may need to try the cover and the identity page.

The simulator and iPad can display the interface and import an archive, but cannot perform NFC reading. The current manual entry flow does not support extended document numbers longer than nine characters or TD2 documents.

## Privacy and storage

A `PassportRecord` may contain identity details, the portrait, MRZ, data groups read from the chip, the SOD, the NFC reading date and technical verification results.

- Local data uses AES-256-GCM, complete iOS file protection and a key stored in Keychain.
- SesamePass locking is disabled by default and can be enabled in Settings.
- Vision scans and NFC exchanges are processed locally.
- The app contains no third-party server integration, advertising, analytics or tracking.
- PDF exports display “Digital copy — does not replace a travel document.”
- SesamePass archives are password-protected and can be imported without an Apple account.

When enabled and configured, iCloud backup uses the private CloudKit database. Data is encrypted before upload; CloudKit receives a `CKAsset` containing the encrypted payload. The backup key is stored in synchronizable iCloud Keychain. The app remains fully usable when backup is disabled or while offline.

## Verification scope

SesamePass verifies the SOD signature and compares the hashes of data groups that were actually read. **No national certificate trust list is bundled with the app.** SesamePass therefore cannot independently establish trust in the issuing country; this check is shown as “Not performed.”

## Build the project

Requirements: Xcode, iOS 18 or later, and Swift 6.

1. Open `SesamePass.xcodeproj`.
2. Select the **SesamePass** scheme.
3. Choose an Apple Developer team under **Signing & Capabilities**.
4. Make sure **Near Field Communication Tag Reading** is enabled for the App ID and included in the provisioning profile.
5. Build on a physical iPhone to test NFC reading.

The ISO 7816 entitlements are already configured. Xcode resolves OpenSSL-Package during the first build.

```sh
xcodebuild -project SesamePass.xcodeproj \
  -scheme SesamePass \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build

swift test
```

The reader uses a local copy of NFCPassportReader 2.3.3 under the MIT license, with logging disabled and targeted fixes applied. OpenSSL-Package is pinned to version 3.6.3000. See [reader modifications](Vendor/NFCPassportReader/SESAME-PATCHES.md).

## Documentation

- [NFC reading and test procedure](Documentation/NFC.md)
- [Security and key recovery](Documentation/SECURITY.md)
- [iCloud configuration](Documentation/ICLOUD.md)
- [Validation](Documentation/VALIDATION.md)

# Local integration

Source: https://github.com/AndyQ/NFCPassportReader
Version: 2.3.3, commit 6e37f1ab249fef82771da46d32707f2b94ed090f (MIT).

Only Sources and the license are vendored; no example app, sample passports, sample trust lists or network download scripts.

Sésame changes:

- Every Logger uses OSLog.disabled. The ASN.1 sample diagnostic print is removed, including in Debug builds.
- NFC checked continuation is registered before the session begins, to avoid a callback-before-registration race.
- Failed data-group removal uses removeAll matching the group, rather than removeFirst on a possibly empty/unrelated list.
- CardAccess exposes the original bytes for inclusion inside the encrypted technical archive.
- Local package pins OpenSSL-Package 3.6.3000 exactly (revision a3809db22a45e3ff658377a24da252982a306b9b, upstream binary checksum 6c4b064d12b8de2ae77ac59fbcbbd1c20b4fecfb7fc50b8ab326347c52ecbf0c) and includes the privacy manifest as a resource.

OpenSSL is linked into the app for the passport protocols; this is not a remote service. Only developer builds download dependencies. There are no runtime network requests in these Swift sources. Do not replace with an unpatched remote package: that would reintroduce sensitive diagnostic logs.

Keep this file and the original license when updating. Upstream deprecation warnings for OpenSSL legacy primitives are currently expected; this integration is not an independent security audit of the reader or its parsers.

Preserve the initial PACE failure if the subsequent BAC fallback also fails, so the application can report the actual protocol failure. No APDU content or secrets are logged.

Détection des cartes : le parcours Carte d’identité utilise la découverte Core NFC PACE (.pace seule avant iOS 26.4, .pace + .iso14443 à partir de 26.4). Le parcours Passeport conserve .iso14443. La notification de détection est émise dès didDetect avant connect, pour distinguer absence de détection et échec de connexion. Aucune modification des algorithmes PACE ni ajout du CAN dans cette correction. Référence : https://developer.apple.com/documentation/corenfc/nfctagreadersession/pollingoption/pace . Validation radio sur carte réelle encore nécessaire.

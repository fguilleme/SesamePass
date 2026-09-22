# SesamePass

Lecteur de passeports biométriques pour iPhone, avec bibliothèque locale chiffrée. SwiftUI, iOS 18+, Swift 6. L’application s’ouvre directement sur les passeports ; aucun écran « coffre » par défaut.

## Utilisation

1. Toucher **Lire un passeport**.
2. Scanner la page d’identité avec l’appareil photo, ou saisir le numéro et les dates de naissance/expiration au format JJ/MM/AAAA.
3. Vérifier les trois informations puis toucher **Lire la puce NFC**.
4. Poser le haut de l’iPhone contre la couverture ou la page d’identité, puis rester immobile jusqu’à la fin.
5. Le passeport est enregistré localement et sa fiche s’ouvre. La sauvegarde CloudKit chiffrée se lance ensuite si elle est activée et configurée.

La lecture NFC nécessite un iPhone compatible et un passeport biométrique TD3. Sur iPad/simulateur, la consultation et l’import restent accessibles ; la lecture NFC est indisponible. Les numéros étendus de plus de neuf caractères et les documents TD1/TD2 ne sont pas pris en charge par la saisie actuelle.

## Réglages

**Verrouiller SesamePass** est désactivé par défaut. Son activation et sa désactivation sont confirmées avec Face ID, Touch ID ou le code appareil. Lorsque l’option est active, une authentification est demandée au retour dans l’application. Le stockage reste chiffré et protégé par iOS dans les deux modes. Un code appareil reste nécessaire pour créer la clé locale liée à ce code.

**Sauvegarde iCloud** conserve le fonctionnement existant : base privée, données chiffrées avant envoi, clé de sauvegarde dans le Trousseau synchronisable, mode OFF, restauration explicite et suppressions différées hors ligne.

## Ouvrir et compiler

Ouvrir `SesamePass.xcodeproj`, scheme **SesamePass**. Conserver votre équipe Apple Developer dans Signing & Capabilities. La capability **Near Field Communication Tag Reading** doit être autorisée pour cet App ID et présente dans le profil de signature. Les entitlements et l’identifiant ISO7816 du passeport sont déjà déclarés dans le projet. Xcode résout OpenSSL lors de la première compilation.

```sh
xcodebuild -project SesamePass.xcodeproj -scheme SesamePass -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
swift test
```

Le simulateur ne peut pas valider une lecture radio, l’appareil photo ni la récupération du Trousseau entre appareils. Le service CloudKit est volontairement désactivé pour les builds simulateur sans droits iCloud ; les essais de sauvegarde sont à effectuer sur appareils signés.

## Stockage et exports

- PassportRecord : identité, photographie, MRZ, Data Groups lus, SOD, date NFC, résultats des contrôles et preuves techniques optionnelles.
- AES-256-GCM local, protection complète iOS, clé locale Keychain liée au code appareil, exclusion des backups système.
- CloudKit Private Database : seul champ applicatif `payload`, CKAsset déjà chiffré.
- PDF lisible avec avertissement avant partage et mention « Copie numérique — ne remplace pas un document de voyage. »
- Archive chiffrée par mot de passe, importable sans compte Apple, comprenant aussi les preuves NFC conservées. Les anciennes archives restent compatibles.
- Aucun serveur tiers, analytics, tracking ou publicité. Le scan Vision et les opérations NFC sont locaux.

## Vérifications et limites

PACE/BAC, lecture des groupes disponibles hors biométrie réservée, signature du SOD, empreintes des groupes lus, Chip Authentication et Active Authentication lorsque disponibles. **Aucune liste de certificats nationaux de confiance n’est embarquée : le pays émetteur n’est donc pas certifié.** Ce résultat est explicitement « Non effectuée », jamais transformé en succès.

Le code du lecteur NFCPassportReader 2.3.3 (MIT) est intégré localement avec ses journaux désactivés et des corrections ciblées ; OpenSSL-Package est fixé à 3.6.3000. Aucune dépendance ne reçoit de données en réseau. Voir [les modifications du lecteur](Vendor/NFCPassportReader/SESAME-PATCHES.md).

[Lecture NFC et recette](Documentation/NFC.md) · [Récupération des clés](Documentation/SECURITY.md) · [Configuration iCloud](Documentation/ICLOUD.md) · [Validation](Documentation/VALIDATION.md)

Cartes d’identité : le parcours Ajouter un document prend aussi en charge le format électronique TD1 via la MRZ du verso. Voir Documentation/NFC.md pour les limites de compatibilité et les tests à effectuer sur appareil.

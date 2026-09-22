# Sécurité et récupération des clés

## Données locales

Le dossier Application Support/Sesame est exclu des sauvegardes système et protégé par `NSFileProtectionComplete`. Le coffre `vault.sealed` est écrit atomiquement avec protection complète. Il contient le tableau des PassportRecord, les références CloudKit et la file des suppressions, entièrement sérialisés puis chiffrés par CryptoKit AES-256-GCM. Aucun nom, MRZ ou portrait dans les noms de fichiers, préférences ou journaux.

La clé locale de 256 bits est créée avec le générateur de CryptoKit, puis conservée dans un item Generic Password du Keychain, service `app.sesame.passports.keys.v1`, compte `local-vault`, **non synchronisable**, accessibilité **kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly**. Sa perte ne bloque pas la restauration CloudKit, qui repose sur d’autres clés. La suppression du code appareil peut rendre ce coffre local irrécupérable : ne pas retirer le code avant d’avoir vérifié une sauvegarde récupérable.

L’application charge les données locales directement par défaut. Le réglage « Verrouiller SesamePass » est optionnel et désactivé par défaut ; son activation/désactivation exige `.deviceOwnerAuthentication`. Lorsque ce réglage est actif, le retour à l’application exige une authentification. Le code appareil sert de repli à Face ID/Touch ID. Cette préférence ne modifie ni le chiffrement local, ni les attributs des clés. Les enregistrements en mémoire sont retirés de l’état applicatif lors du passage en arrière-plan. Swift/Data ne garantissent pas l’effacement immédiat de toutes les copies mémoire ; aucun effacement sécurisé de mémoire n’est revendiqué. Le masquage de l’aperçu multitâche ne bloque pas une capture d’écran volontaire.

## Clés iCloud

Chaque nouvelle sauvegarde reçoit deux UUID aléatoires : identifiant de record CloudKit et identifiant de clé. Une clé AES-256 indépendante est stockée dans le même service Keychain sous le compte égal à cet identifiant de clé, avec **kSecAttrSynchronizable = true** et **kSecAttrAccessibleWhenUnlocked**. On ne combine pas synchronisation et attribut `ThisDeviceOnly` pour ces clés.

Le payload CloudKit est une enveloppe JSON : version, UUID opaque de sauvegarde, UUID opaque de clé et octets AES-GCM combinés (nonce, ciphertext, tag). Tous les champs de PassportRecord sont à l’intérieur du ciphertext. Version et UUID sont liés au ciphertext par les données authentifiées supplémentaires d’AES-GCM. Aucune valeur secrète de clé dans CloudKit, même dans un autre champ du record.

L’item est éligible à la synchronisation du Trousseau iCloud. Apple assure le transport et la récupération de ce trousseau avec chiffrement de bout en bout. L’application n’a **aucune API publique attestant que la clé a effectivement atteint un second appareil**. Un ajout Keychain réussi n’est donc pas une preuve de restauration possible. Le statut « Sauvegardé dans iCloud » confirme l’envoi du blob, pas une réplication vérifiée de la clé. Cette distinction est indiquée dans les réglages.

La protection biométrique est une porte d’accès applicative ; les clés synchronisables ne portent pas de contrainte `biometryCurrentSet`. Cela évite de les rendre inutilisables après changement d’appareil ou de biométrie et permet les reprises silencieuses tant que les données locales sont chargées et que l’application est active. Cette architecture ne revendique pas une clé AES non exportable du Secure Enclave.

## Qui peut récupérer

Les appareils autorisés du même compte Apple, avec Mots de passe et Trousseau iCloud activé, déverrouillés et ayant reçu l’item Keychain, peuvent le retrouver dans le groupe d’accès de cette application signée. Le même Bundle ID et préfixe d’équipe/groupe Keychain doivent être conservés. Changer d’équipe, d’identifiant ou de droits sans migration peut bloquer l’accès. SesamePass ne fournit pas de service serveur capable de restituer une clé.

Après perte de tous les appareils, la récupération dépend des mécanismes Apple de récupération du Trousseau et des justificatifs configurés par l’utilisateur. Se reconnecter au compte iCloud ne suffit pas toujours à déverrouiller les données chiffrées de bout en bout.

## Cas irrécupérables

- Clé jamais synchronisée avant la perte du dernier appareil qui la détenait (Trousseau désactivé, synchronisation inachevée).
- Réinitialisation des données chiffrées iCloud ou suppression définitive de l’item Keychain, sans autre copie de clé.
- Impossibilité de récupérer le compte/Trousseau avec les mécanismes Apple configurés.
- Suppression de la sauvegarde CloudKit et absence de copie locale ou d’archive.
- Pour une archive indépendante : perte de son mot de passe ou fichier endommagé.

Une clé introuvable en restauration n’est **jamais remplacée** par une clé nouvelle. Le blob reste intact et l’utilisateur est invité à activer/attendre le Trousseau d’origine. Les anciennes clés synchronisables ne sont pas supprimées automatiquement lors de la suppression d’un passeport, pour éviter des effets de bord sur d’autres appareils. Elles ne suffisent pas à retrouver un blob supprimé.

## Mode iCloud OFF

Aucun nouveau travail CloudKit ni création de clé synchronisable. Les opérations déjà remises au système peuvent se terminer ; le code refuse les étapes suivantes et les retours d’une ancienne session. Les éléments déjà synchronisables restent gérés par iOS ; désactiver l’option ne les retire pas du Trousseau iCloud et ne supprime pas les backups existants. Pour un usage local dès le départ, désactiver l’option avant d’importer le premier passeport.

Les suppressions cloud demandées en mode OFF sont mises en attente. Il faut réactiver iCloud pour les exécuter, ce que précise la confirmation. Si l’app est désinstallée avant exécution, cette file locale est perdue et la sauvegarde distante demeure.

## Exports

Le PDF est explicitement **en clair** après confirmation. Il ne contient pas les DG/MRZ/SOD bruts, seulement les données lisibles prévues. Fichier temporaire protégé, suppression à la fin du partage et au prochain lancement. Une copie remise à une destination de partage n’est plus contrôlée par SesamePass.

L’archive indépendante contient le PassportRecord entier chiffré par AES-256-GCM. Clé dérivée du mot de passe par PBKDF2-HMAC-SHA256 (CommonCrypto Apple), 600 000 itérations, sel aléatoire de 32 octets, nonce GCM neuf. Mot de passe minimal de 12 caractères, confirmation demandée. Format, version et nombre d’itérations strictement vérifiés. Un mot de passe long et unique reste nécessaire contre les attaques hors ligne. Le mot de passe et la clé dérivée ne sont pas enregistrés. L’import crée une copie distincte et ne remplace pas un passeport local.

## Réseau et vérifications

Le seul code réseau applicatif utilise CloudKit Private Database ; aucune URLSession, SDK tiers ou télémétrie. Le Trousseau iCloud est géré par iOS. Le partage natif est une action explicite de l’utilisateur et peut envoyer le fichier à la destination qu’il choisit.

Pas de téléchargement automatique de certificats ou de listes ICAO depuis un tiers. La lecture NFC vérifie la signature du SOD et les empreintes des groupes lus ; la constitution d’une base CSCA de confiance hors ligne reste à faire. Une signature SOD valide ne prouve pas la confiance dans le certificat signataire. Le résultat « Confiance dans le pays émetteur » reste explicitement « Non effectuée ». Voir NFC.md pour le détail des contrôles et de leurs limites.

## Références Apple

- [kSecAttrSynchronizable](https://developer.apple.com/documentation/security/ksecattrsynchronizable)
- [Accessibilité du Keychain](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
- [Sécurité du Trousseau iCloud](https://support.apple.com/en-au/guide/security/sec1c89c6f3b/web)
- [Récupération sécurisée du Trousseau](https://support.apple.com/en-in/guide/security/secdeb202947/web)
- [CloudKit et chiffrement](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)

Le chiffrement applicatif AES-GCM est appliqué avant CloudKit, indépendamment du chiffrement que CloudKit apporte lui-même aux CKAsset.

## Identité SesamePass

Le Bundle ID est désormais `com.guilleme.sesamepass`. Le conteneur `iCloud.app.sesame.passports`, le nom de service Keychain, le dossier local et les marqueurs cryptographiques du format `.sesame` sont volontairement conservés. Ce sont des identifiants de stockage, pas le nom public de l’application.

Le changement de Bundle ID crée une application distincte sur iOS : le bac à sable et le groupe Keychain par défaut de l’ancienne application ne sont pas transférés. Conserver le conteneur CloudKit ne donne pas accès aux anciennes clés. Avant de supprimer l’ancienne installation, exporter une archive chiffrée et conserver son mot de passe, puis l’importer dans SesamePass. Aucune migration automatique entre les deux identifiants n’est revendiquée. Le nouvel App ID doit être associé au conteneur existant et à NFC dans le compte Apple Developer.

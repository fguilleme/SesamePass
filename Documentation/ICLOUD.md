# Configuration iCloud et CloudKit

1. Dans Xcode, sélectionner une équipe Apple Developer payante dans Signing & Capabilities. L’identifiant de l’application est `com.guilleme.sesamepass`. Autoriser iCloud et NFC pour cet App ID.
2. Activer la capability iCloud, service CloudKit, conteneur `iCloud.app.sesame.passports`. Si le conteneur doit être renommé, modifier également `CloudBackup.swift` et `Configuration/SesamePass.entitlements`.
3. Le Keychain utilise le groupe d’accès par défaut de l’app signée ; aucun partage avec une autre application. Conserver Bundle ID et équipe lors des mises à jour.
4. Dans CloudKit Console, environnement Development, définir le record type **EncryptedPassport** avec un seul champ applicatif **payload: Asset**. Aucun champ d’identité, photographie, MRZ, DG, SOD, numéro ou date de naissance.
5. Ajouter l’index **QUERYABLE** sur `recordName` pour les requêtes de découverte avec `NSPredicate(value: true)`. La date affichée vient de `modificationDate`, métadonnée système. Toutes les pages de la requête sont lues ; aucun tri serveur spécifique requis.
6. Toutes les opérations passent par `privateCloudDatabase`. Ne pas ajouter de partage public ou de CKShare. Tester avec des comptes de test sur appareils physiques avant de déployer le schéma en Production.
7. Pour TestFlight/App Store, utiliser les entitlements de distribution et l’environnement CloudKit Production selon le profil généré par Xcode. Le fichier livré indique Development pour les essais ; adapter cette valeur pour une archive de distribution. Déployer le schéma avant diffusion.

## Comportement

Les modifications locales sont écrites avant le lancement d’une tâche réseau. Les UUID de clé et référence sont persistés avant l’upload, ce qui permet une reprise idempotente après arrêt. Les uploads utilisent `ifServerRecordUnchanged`, et vérifient la révision déchiffrée du dernier record distant connu avant écrasement. Un conflit laisse les deux états intacts et signale l’échec ; la fusion multi-appareils n’est pas implémentée. Pour récupérer un état distant en conflit, exporter d’abord une archive locale, supprimer seulement de cet iPhone, puis restaurer la sauvegarde proposée.

Les reprises ont lieu après enregistrement, activation d’iCloud, retour au premier plan, et toutes les 45 secondes tant que l’app est active et que les données locales sont chargées. Il n’y a pas de garantie d’exécution en arrière-plan ou lorsque l’iPhone est verrouillé. L’application reste utilisable hors ligne et n’exige aucun bouton de sauvegarde.

Les références sont liées à l’identifiant opaque du compte CloudKit. Un autre compte ne reçoit pas automatiquement les passeports déjà liés au premier. Les changements de compte ferment la session locale ; elle est rechargée automatiquement si le verrouillage optionnel est désactivé, sinon une authentification est nécessaire ; les suppressions attendent le compte d’origine. Le mode OFF empêche les étapes réseau suivantes, mais ne peut rappeler une requête déjà remise au service Apple.

La découverte ne charge que les métadonnées système (UUID, date). L’utilisateur doit demander la restauration avant de télécharger et déchiffrer le contenu. Une interruption permet de reprendre les records restants ; les passeports déjà restaurés sont persistés individuellement.

## Métadonnées visibles à CloudKit

Record type, UUID aléatoire, propriétaire système, dates système, taille de l’asset et enveloppe de chiffrement (version, deux UUID aléatoires, nonce/tag/ciphertext). Aucun hachage de nom ou numéro de passeport. Les métadonnées peuvent révéler le nombre de sauvegardes et leur activité ; aucun anonymat de ces métadonnées n’est revendiqué.

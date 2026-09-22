# Validation — 22 septembre 2026

## Exécuté

- Xcode 27.0 (27A266a), build Debug iOS Simulator réussi, code Swift 6.
- 30 tests Swift Testing réussis sur macOS ; fixtures synthétiques (dont tests paramétrés).
- Compilation Debug iPhone (iphoneos) réussie, sans signature de distribution.
- Vérification en simulateur : ouverture directe sans écran de verrouillage, bouton Lire un passeport, formulaire à trois champs, saisie synthétique, fermeture, option Verrouiller SesamePass désactivée par défaut, déclenchement de la confirmation système à son activation.
- MRZ TD3 : cas ICAO public, chiffrement d’accès/padding, sommes de contrôle individuelles et composite, dates invalides, OCR fragmenté, caractères ambigus refusés.
- Vérifications NFC : couverture incomplète des empreintes et signature invalide ne deviennent pas des succès ; absence de CSCA reste non vérifiée. Compatibilité des anciens records et aller-retour chiffré des preuves NFC.
- Aller-retour de tous les champs du PassportRecord, dont photo, DG et SOD.
- Nonce distinct pour chaque chiffrement du même contenu.
- Rejet de mauvaise clé, payload/tag altéré, substitution de record, changement d’UUID de clé et version inconnue.
- Export/import d’archive avec mot de passe correct, rejet de mauvais mot de passe, mot de passe trop court, altération et paramètres KDF hostiles.

Ces tests ne sont ni un audit de sécurité indépendant ni une validation réelle CloudKit.

## Recette sur appareils à effectuer après configuration Apple

Utiliser des documents synthétiques tant que cette recette n’est pas terminée.

1. Sur iPhone A, activer code et Trousseau iCloud. Importer une archive de test ; vérifier le stockage immédiat puis la présence du CKAsset dans la base privée. Inspecter le schéma : seul `payload` doit être applicatif et son contenu doit être une enveloppe AES-GCM, jamais un JSON PassportRecord lisible.
2. Couper le réseau, créer/modifier via `PassportStore.save(_:)`, forcer l’arrêt, relancer : données locales conservées, sauvegarde en attente. Réactiver le réseau et garder le données locales chargées : upload sans bouton.
3. Sur iPhone B, même compte Apple et même app signée, Trousseau activé : proposition avec nombre/date avant affichage de l’identité ; restaurer, comparer tous les champs et octets DG/SOD/photo.
4. Refaire après suppression/réinstallation de l’app et après suppression de la clé locale sur un appareil de test. La clé locale ne doit pas être nécessaire au déchiffrement de CloudKit.
5. Restaurer avec le Trousseau indisponible : erreur explicite, aucun remplacement de clé, aucun écrasement de blob. Vérifier le succès après arrivée de la clé.
6. Mode OFF : aucune opération CloudKit initiée par l’app ; imports/exports et stockage local fonctionnels. Vérifier que les clés déjà synchronisables restent sous le contrôle d’iOS, conformément à l’avertissement.
7. Supprimer localement : le record distant reste. Supprimer localement et dans iCloud : vérifier son absence effective dans CloudKit Console. Refaire hors ligne, après arrêt forcé, puis après réactivation d’iCloud. L’état en attente doit rester visible dans les réglages.
8. Changer de compte iCloud pendant un upload/restauration : session locale fermée ; pas de validation du résultat dans une nouvelle session ; références de l’ancien compte suspendues.
9. Modifier une même sauvegarde depuis deux appareils : vérifier le refus d’écrasement concurrent. Préserver les deux versions via archives avant résolution manuelle.
10. Tester OFF et verrouillage pendant upload, pagination supérieure à 100 records, quotas CloudKit, CKAsset absent/corrompu, erreur Keychain, disque plein et indisponibilité des fichiers protégés.
11. PDF : photographie proportionnée, caractères accentués, pagination, avertissement sur chaque page, résultats exacts sans réussite inventée. Partage et annulation nettoient le fichier temporaire.
12. Archive : export puis import sur un appareil d’un autre compte Apple, avec le mot de passe seulement. Mauvais mot de passe = refus sans données affichées.
13. Protection optionnelle ON/OFF : Face ID et code de repli, refus/annulation, passage en arrière-plan, aperçu multitâche, Dynamic Type, VoiceOver, iPad.

## Limites connues

- Lecteur NFC intégré ; lecture radio, OCR caméra et biométrie réelle à valider sur iPhone selon NFC.md. Aucun succès de lecture physique revendiqué.
- Pas de liste CSCA : la confiance dans le pays émetteur n’est pas vérifiée. Support de la saisie/scan limité aux passeports TD3 avec numéro de 9 caractères maximum.
- Le package NFCPassportReader utilise encore des API OpenSSL dépréciées : avertissements de compilation en amont, pas d’erreur bloquante.
- Conteneur et schéma CloudKit non provisionnés par cette création de projet.
- Pas de fusion multi-appareils ni de propagation automatique d’une suppression aux copies locales d’autres appareils. Une copie conservée sur un autre appareil peut être sauvegardée à nouveau après modification.
- Synchronisation automatique uniquement pendant l’utilisation du données locales chargées ; une sauvegarde en attente ne survit à la perte de l’appareil que si le blob et sa clé ont réellement été transmis auparavant.
- Les reprises périodiques utilisent un intervalle fixe de 45 secondes ; une politique avancée de backoff serveur reste à développer si les quotas l’exigent.
- Export PDF des valeurs textuelles extrêmement longues à vérifier ; les limites d’entrée d’un futur lecteur devront correspondre au format ICAO.

## Validation sur appareil — 22 septembre 2026

L’utilisateur confirme le fonctionnement de la lecture NFC de sa carte d’identité après activation de la découverte PACE dans le parcours Carte d’identité. Cette validation concerne la carte essayée, pas toutes les cartes TD1. Compilation iPhone signée réussie après la correction. La dernière suite de tests exécutée comprend 44 tests réussis (MRZ, OCR synthétique, archives et chiffrement).

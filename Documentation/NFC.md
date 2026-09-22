# Lecture NFC — version 0.2

## Flux

`AddPassportView` obtient les trois champs manuellement ou via la caméra native VisionKit et une reconnaissance Vision locale. Les deux lignes TD3 sont vérifiées : longueurs, caractères, chiffres de contrôle du numéro, dates, champ optionnel et somme composite. Aucune correction approximative O/0 ou I/1. Les pixels de la page restent en mémoire pour l’OCR ; ils ne sont ni enregistrés ni envoyés.

`MRZAccess` forme la clé d’accès standard, y compris le remplissage `<` du numéro. Les dates saisies sont validées dans un calendrier grégorien strict. L’année sur deux chiffres vient de la MRZ ; le siècle affiché est inféré, il ne fait pas partie des octets d’accès. Vérifier la date complète sur les passeports de personnes centenaires.

`NFCReadingService` crée un lecteur par session. Core NFC utilise ISO14443/ISO7816, application A0000002471001. Les messages système sont en français. Le lecteur tente PACE (Generic Mapping pris en charge en amont), avec BAC en repli. Il lit les groupes pris en charge annoncés par COM, sauf DG3/DG4 réservés aux terminaux autorisés. CA/AA sont effectuées lorsque prises en charge.

Le résultat exige au minimum DG1, DG2 et SOD, et la MRZ lue doit correspondre aux informations d’accès. Une lecture partielle n’est pas enregistrée. En cas de panne de stockage après une lecture réussie, la fiche demeure en mémoire dans l’écran pour permettre un nouvel essai d’enregistrement sans relire la puce. Un changement de session applicative invalide la prise en compte d’un résultat NFC tardif.

Le record est sauvegardé avant affichage de la fiche et avant l’envoi CloudKit. La photo est conservée dans son encodage natif ; les groupes bruts, SOD, CardAccess, empreintes et réponse/défi AA sont inclus dans les données chiffrées. Aucun secret de session PACE/BAC n’est archivé.

## Ce que signifient les contrôles

- PACE/BAC : accès sécurisé, pas une preuve d’identité du pays.
- Signature SOD : vérification avec le certificat fourni par le passeport, pas validation de confiance de ce certificat.
- Intégrité : couverture de tous les groupes effectivement lus et comparaison de leurs empreintes avec le SOD.
- Confiance nationale : **non effectuée** tant qu’une liste CSCA fiable et actualisée n’est pas embarquée.
- CA/AA : possession de la clé de puce lorsque le document et le lecteur permettent le protocole ; ne remplace pas la chaîne de confiance.

Il n’y a aucun téléchargement de certificat, vérification OCSP ou CRL depuis un service tiers. Un contrôle absent n’est pas un succès. Une lecture ayant des contrôles échoués peut être conservée, avec ces échecs visibles dans la fiche et le PDF.

## Configuration de signature

- Entitlement `com.apple.developer.nfc.readersession.formats = [TAG]`.
- Info.plist : `NFCReaderUsageDescription`, `NSCameraUsageDescription`, `com.apple.developer.nfc.readersession.iso7816.select-identifiers = [A0000002471001]`.
- Activer **Near Field Communication Tag Reading** pour l’identifiant de l’app dans votre équipe Apple Developer, puis actualiser le profil de signature si Xcode le demande.
- Pas de capability NFC & SE Platform / paiement / émulation nécessaire : l’application ne fait que lire un document ISO7816.

## Recette physique nécessaire

1. Test avec un passeport TD3 de test, code appareil configuré et réseau coupé. Comparer identité, dates et photographie avec le document ; relancer l’app et retrouver le record.
2. Saisie manuelle et scan de la page. Tester refus caméra, reflets, ligne coupée, caractères OCR ambigus et données saisies erronées.
3. Annuler dans l’interface NFC, éloigner le passeport, attendre le délai, présenter plusieurs puces ; vérifier le message et l’absence de record incomplet.
4. Vérifier un passeport PACE, un BAC, un avec CA et un avec AA ; inspecter chaque contrôle sans assimiler leur résultat à une chaîne CSCA validée.
5. Passer en arrière-plan pendant lecture/enregistrement ; aucune sauvegarde d’un résultat d’une ancienne session après réouverture.
6. Exporter l’archive, réimporter et comparer les octets des DG/SOD/épreuves AA. Les fixtures automatiques sont synthétiques, aucun document personnel dans le dépôt.
7. Activer la protection dans les réglages sur appareil : accepter/refuser Face ID, tester code de repli, retour arrière-plan et désactivation authentifiée. Vérifier l’ouverture directe lorsque l’option est OFF.

## Sources

- [Lecteur NFCPassportReader](https://github.com/AndyQ/NFCPassportReader/tree/6e37f1ab249fef82771da46d32707f2b94ed090f)
- [Core NFC : NFCISO7816Tag](https://developer.apple.com/documentation/corenfc/nfciso7816tag)
- [Identifiants d’application ISO7816](https://developer.apple.com/documentation/corenfc/nfctagreadersession/configuration/iso7816selectidentifiers)

### Reconnaissance de la photo

Vision traite uniquement en mémoire la page confirmée dans le scanner iOS (Conserver le scan, puis Enregistrer). Les blocs d’une même ligne sont réunis de gauche à droite ; jusqu’à trois propositions par bloc sont examinées, avec une limite de 81 combinaisons par ligne. Les données d’accès sont extraites de la deuxième ligne TD3, même si la ligne du nom est mal reconnue. Les confusions O/0, I/1, L/1, Z/2, S/5 et B/8 ne sont corrigées que dans les positions numériques. Tous les chiffres de contrôle de cette ligne, y compris le contrôle optionnel et composite, doivent réussir. Plusieurs résultats d’accès distincts entraînent un refus. Le numéro alphanumérique n’est jamais deviné.

Cette étape préremplit les champs à vérifier ; elle ne prouve pas l’authenticité du passeport. La lecture NFC et la validation stricte de la MRZ lue dans la puce restent nécessaires pour enregistrer le document. Aucun texte reconnu ni image n’est journalisé. API : https://developer.apple.com/documentation/vision/vnrecognizedtextobservation/topcandidates(_:)

Si le mode Vision « accurate » ne produit pas de ligne validée, une deuxième analyse en mode « fast » est effectuée en mémoire. Ce mode peut mieux préserver les suites de chevrons MRZ. Les mêmes contrôles restent obligatoires. Régression reproduite localement sur la capture utilisateur fournie : échec avec accurate seul, succès avec le repli fast. L’image et son texte ne sont pas intégrés au dépôt ni aux fixtures de test. Le retour réel de la caméra sur iPhone reste à vérifier sur appareil.

## Cartes d’identité TD1

Choisir Ajouter un document > Carte d’identité, scanner les trois lignes du verso (ou saisir numéro, naissance et expiration), puis lire la puce NFC. Le type du document est conservé dans le payload chiffré local, CloudKit et archive et affiché dans la fiche et le PDF. Les anciens enregistrements sans type restent des passeports. Aucun champ CloudKit supplémentaire.

Le parseur TD1 contrôle le numéro, les deux dates et le chiffre composite selon ICAO 9303 partie 5 (https://www.icao.int/publications/Documents/9303_p5_cons_en.pdf). Les corrections OCR concernent seulement les positions numériques, avec rejet des résultats ambigus. Après NFC, la MRZ DG1 doit être du format choisi et correspondre aux informations d’accès ; DG1, DG2 et SOD restent obligatoires. La photo OCR ne constitue jamais un document enregistré.

Périmètre : cartes électroniques TD1 avec accès eMRTD par MRZ, BAC ou PACE-GM pris en charge par la bibliothèque. Pas de CAN/PIN, PACE-IM, TD2, anciennes CNI françaises sans puce ou numéros étendus de plus de neuf caractères. Compatibilité physique CNIe française à confirmer sur appareil ; ce n’est pas une intégration France Identité. Les empreintes ne sont pas lues. Tests réalisés sur spécimens synthétiques uniquement.

Détection des cartes : le parcours Carte d’identité utilise la découverte Core NFC PACE (.pace seule avant iOS 26.4, .pace + .iso14443 à partir de 26.4). Le parcours Passeport conserve .iso14443. La notification de détection est émise dès didDetect avant connect, pour distinguer absence de détection et échec de connexion. Aucune modification des algorithmes PACE ni ajout du CAN dans cette correction. Référence : https://developer.apple.com/documentation/corenfc/nfctagreadersession/pollingoption/pace . Validation radio sur carte réelle encore nécessaire.

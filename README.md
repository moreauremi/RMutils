# RMutils

Boîte à outils de maintenance Windows qui tient sur une clé USB : un seul fichier `.bat` par version, un menu au clavier, et une trace de chaque PC dépanné (logs, rapports HTML, sauvegardes).

Le menu principal (en vrai, il est en couleur) :

```text
   ____  __  __       _   _ _
  |  _ \|  \/  |_   _| |_(_) |___
  | |_) | |\/| | | | | __| | / __|
  |  _ <| |  | | |_| | |_| | \__ \
  |_| \_\_|  |_|\__,_|\__|_|_|___/
  PC-EXEMPLE  |  Windows 11 Professionnel 24H2 (build 26100)
  ==========================================================================
  Menu principal

  > 1  Mises a jour
    2  Diagnostic
    3  Nettoyage
    4  Reparation
    5  Sauvegarde et restauration
    6  Installation
    7  Outils
    0  Quitter

  --------------------------------------------------------------------------
  Windows Update, mises a jour des applications (winget), ou les deux.
  Reglage du redemarrage automatique.
  --------------------------------------------------------------------------
  Fleches : naviguer   Entree : valider   1-9 : acces direct   Echap : retour
```

## Deux versions

| | `RMutils.bat` | `RMutils_Lite.bat` |
|---|---|---|
| Droits | Administrateur (demande UAC au lancement) | Aucun droit admin |
| Mises à jour Windows | Recherche et installe tout | Liste les mises à jour en attente, ouvre Paramètres |
| Santé des disques | SMART : température, usure, erreurs de lecture | État, type et capacité |
| Nettoyage | Temporaires, cache Windows Update, composants (WinSxS) | Fichiers du compte, caches des navigateurs |
| Réparation | DISM, SFC, reset Windows Update et réseau, chkdsk | Cache DNS, Explorateur, cache des icônes, Microsoft Store |
| Wi-Fi | Export avec mots de passe, restauration, QR code | Liste des réseaux, restauration |

Le reste (diagnostic, mise à jour des applications, pack d'applications) est commun aux deux. Elles partagent la même liste d'applications (`RMutils_apps.txt`) et les mêmes dossiers sur la clé.

## Fonctionnalités de la version complète

**Mises à jour**
- Windows Update sans passer par Paramètres : recherche, téléchargement, puis installation une par une avec un statut pour chacune. Jusqu'à 3 passes si de nouvelles mises à jour apparaissent.
- Mise à jour silencieuse de toutes les applications connues de winget.
- Redémarrage automatique activable (après 60 s, annulable avec `shutdown /a`).

**Diagnostic** (rien n'est modifié sur le PC)
- Infos système : modèle, n° de série, version et activation de Windows, uptime, processeur, mémoire, carte graphique, carte mère, BIOS, espace disque.
- Santé des disques (SMART) : état, température, usure des SSD, heures de fonctionnement, erreurs de lecture.
- Batterie : capacité d'origine comparée à la capacité actuelle, et rapport `powercfg` détaillé.
- Réseau : IP, passerelle, DNS, MAC, puis tests dans l'ordre box → Internet → DNS → web. Le premier test en échec indique où ça coince.
- Rapport HTML complet (système, disques, batterie, réseau, 10 dernières mises à jour) enregistré sur la clé, dans un dossier par PC.

**Nettoyage**
- Rapide : fichiers temporaires (utilisateur et Windows), cache Windows Update, miniatures, rapports d'erreurs, dumps de plantage, cache d'optimisation de distribution, corbeille. Affiche l'espace libéré.
- Composants Windows : `DISM /StartComponentCleanup` sur le dossier WinSxS. Les mises à jour déjà installées ne pourront plus être désinstallées.

**Réparation** (un point de restauration est créé avant chaque action)
- `DISM /RestoreHealth` puis `sfc /scannow`.
- Réinitialisation de Windows Update : arrêt des services, remise à zéro de `SoftwareDistribution` et `catroot2`, redémarrage des services.
- Réinitialisation du réseau : cache DNS, Winsock, piles IPv4 et IPv6.
- `chkdsk /scan` sans redémarrer, avec réparation planifiée au prochain démarrage si des erreurs sont trouvées.

**Sauvegarde et restauration**
- Export et restauration des pilotes tiers (`dism /export-driver`, `pnputil`). À faire avant une réinstallation pour ne pas se retrouver sans Wi-Fi.
- Export et restauration des profils Wi-Fi, mots de passe compris.

**Installation**
- Pack d'applications installées en silencieux via winget, depuis une liste modifiable (`RMutils_apps.txt`). Les applications déjà présentes sont ignorées.

**Outils**
- Mot de passe d'un réseau Wi-Fi enregistré, avec son QR code affiché directement dans le terminal : on le scanne avec un téléphone pour se connecter.

## Utilisation

1. Copier `RMutils.bat`, `RMutils_Lite.bat` et `RMutils_apps.txt` à la racine d'une clé USB.
2. Sur le PC, double-cliquer sur `RMutils.bat` (accepter la demande UAC) ou sur `RMutils_Lite.bat`.
3. Naviguer au clavier : flèches pour se déplacer, Entrée pour valider, 1 à 9 pour un accès direct, Échap ou 0 pour revenir ou quitter.

Prérequis : Windows 10 ou 11 (PowerShell 5.1 est déjà intégré), et winget pour les fonctions liées aux applications.

> Windows peut bloquer un `.bat` téléchargé depuis Internet. Dans ce cas : clic droit sur le fichier, Propriétés, cocher **Débloquer**.

## Ce que RMutils écrit sur la clé

```text
CLE_USB\
├── RMutils.bat
├── RMutils_Lite.bat
├── RMutils_apps.txt        applications à installer, un identifiant winget par ligne
├── RMutils_logs\           un log par session : <nom du PC>_<date>.log
└── RMutils_export\
    └── <nom du PC>\        rapports HTML, rapport batterie, pilotes\, wifi\
```

## Sécurité

- **Les profils Wi-Fi exportés contiennent les mots de passe en clair.** La clé est à traiter comme un support sensible.
- L'outil « Mot de passe Wi-Fi » affiche le mot de passe à l'écran mais ne l'écrit jamais dans le log.
- Les logs et les exports contiennent des infos sur les PC dépannés (nom, n° de série, adresses IP et MAC). Le `.gitignore` les exclut du dépôt.
- Le point de restauration est créé même si Windows en a déjà fait un dans les dernières 24 h : RMutils lève cette limite le temps de la création, puis remet le réglage d'origine. La protection du système est activée si elle était coupée.

## Comment ça marche

Chaque version tient dans un seul fichier, à la fois script batch et script PowerShell. Voici l'en-tête de `RMutils.bat` :

```bat
@echo off
setlocal
title RMutils
set "SELF=%~f0"

:: Auto-elevation en administrateur
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
    exit /b
)

mode con: cols=100
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:SELF); iex $s.Substring($s.LastIndexOf('#PSBEGIN'))"
exit /b

#PSBEGIN
```

- `cmd.exe` exécute l'en-tête : il vérifie les droits avec `net session` et se relance via UAC si besoin. Il lance ensuite PowerShell et s'arrête sur `exit /b`, avant d'atteindre le code PowerShell.
- PowerShell relit le même fichier et exécute tout ce qui suit le marqueur `#PSBEGIN`.
- Résultat : un seul fichier à copier, sans `.ps1` à côté que la stratégie d'exécution de PowerShell pourrait bloquer.

Quelques choix techniques :

- **Windows Update** est piloté par son API COM (`Microsoft.Update.Session`). C'est ce qui permet d'installer les mises à jour une par une et d'afficher un statut pour chacune.
- **winget** ne donne pas de sortie structurée. RMutils lit son tableau texte et repère les colonnes à partir de l'en-tête. Si winget tronque un identifiant trop long, l'application est marquée `IGNORE` plutôt que de risquer de mettre à jour la mauvaise.
- **Le QR code** vient d'un encodeur écrit en C# (versions 1 à 10, correction d'erreur niveau M, codes de Reed-Solomon, choix du masque par score de pénalité), compilé à la volée avec `Add-Type`. Il s'affiche avec les caractères `▀ ▄ █` : chaque ligne du terminal porte deux rangées de modules.
- **Les scripts sont en ASCII, sans accents, avec des fins de ligne Windows (CRLF)**, parce que `cmd.exe` gère mal l'UTF-8 et les fins de ligne Unix. Le fichier `.gitattributes` empêche Git de les convertir.

## Limites

- Windows 10 et 11 uniquement.
- Selon le disque ou le contrôleur (boîtier USB, RAID), certaines infos SMART ne remontent pas.
- Les réseaux Wi-Fi d'entreprise (connexion avec identifiant personnel) n'ont pas de mot de passe stocké : pas de QR code possible.
- Une application ouverte peut échouer à se mettre à jour : mieux vaut fermer les applications avant.

---

Projet personnel de [Rémi Moreau](https://github.com/moreauremi) · [remim.me](https://remim.me)

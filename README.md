# AD-Deployer

**Déploiement et durcissement automatisé d'Active Directory conforme aux recommandations ANSSI.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ansible](https://img.shields.io/badge/Ansible-2.14+-red.svg)](https://www.ansible.com/)
[![Windows Server](https://img.shields.io/badge/Windows%20Server-2019%2F2022-blue.svg)](https://www.microsoft.com/windows-server)

---

## 🚀 Quick Start

```bash
# 1. Cloner le projet
git clone https://github.com/0xsir1s/AD-DEPLOYER.git
cd AD-DEPLOYER/ad-deployer

# 2. Rendre le script exécutable
chmod +x deploy-ad.sh

# 3. Lancer le déploiement
./deploy-ad.sh -t 192.168.1.10 -p 'AdminP@ss!' -s 'DsrmP@ss123!' -d lab.local -n LAB
```

✅ **Active Directory déployé et durci en ~15 minutes !**

---

## 📋 Description

AD-Deployer automatise le déploiement et la sécurisation d'environnements Active Directory selon le modèle de **Tiering ANSSI** (Administration en Tiers).

### Fonctionnalités

| Fonctionnalité | Description |
|----------------|-------------|
| **Déploiement AD** | Création complète forêt/domaine Active Directory |
| **Structure Tiering** | OUs organisées selon le modèle ANSSI (Tier 0, 1, 2) |
| **Groupes & Utilisateurs** | Création automatisée avec appartenance aux groupes |
| **Durcissement ANSSI** | 4 niveaux de sécurité (minimal → paranoid) |
| **GPOs préconfigurées** | Politiques de sécurité prêtes à l'emploi |
| **Logging complet** | Traçabilité de toutes les opérations |

---

## 🏗️ Architecture Tiering ANSSI

```
┌─────────────────────────────────────────────────────────────┐
│  TIER 0 (Critique)                                          │
│  → Contrôleurs de domaine, comptes Domain Admins            │
│  → Accès le plus restreint                                  │
├─────────────────────────────────────────────────────────────┤
│  TIER 1 (Serveurs)                                          │
│  → Serveurs applicatifs, admins serveurs                    │
│  → Isolation des services                                   │
├─────────────────────────────────────────────────────────────┤
│  TIER 2 (Postes)                                            │
│  → Workstations, utilisateurs standards                     │
│  → Moindre privilège                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 Prérequis

### Sur la machine de contrôle (Linux/WSL)

```bash
# Installation des dépendances
sudo apt update && sudo apt install -y ansible python3-pip

# Module Python pour WinRM
pip3 install pywinrm requests-ntlm

# Collections Ansible requises
ansible-galaxy collection install microsoft.ad community.windows ansible.windows
```

### Sur le serveur Windows cible

```powershell
# Activer WinRM (exécuter en admin)
winrm quickconfig -q
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

# Ouvrir le pare-feu (port 5985)
New-NetFirewallRule -Name "WinRM-HTTP" -DisplayName "WinRM HTTP" -Protocol TCP -LocalPort 5985 -Action Allow
```

**Configuration requise :**
- Windows Server 2019 ou 2022
- 4 GB RAM minimum
- PowerShell 5.1+
- Compte administrateur local

---

## 📖 Utilisation

### Syntaxe

```bash
./deploy-ad.sh -t <IP> -p <PASSWORD> -s <SAFE_MODE_PASSWORD> [OPTIONS]
```

### Options obligatoires

| Option | Description | Exemple |
|--------|-------------|---------|
| `-t, --target` | IP du serveur Windows cible | `192.168.1.10` |
| `-p, --password` | Mot de passe admin Windows (WinRM) | `'P@ssw0rd!'` |
| `-s, --safe-mode` | Mot de passe DSRM (récupération AD) | `'Dsrm@123!'` |

### Options de configuration

| Option | Description | Défaut |
|--------|-------------|--------|
| `-d, --domain` | Nom FQDN du domaine | `lab.local` |
| `-n, --netbios` | Nom NetBIOS (max 15 car.) | Auto-généré |
| `-a, --admin` | Compte admin WinRM | `vagrant` |
| `-u, --users` | Nombre d'utilisateurs à créer | `10` |
| `-g, --groups` | Groupes métier (séparés par virgules) | - |
| `-H, --hardening` | Niveau de durcissement | `anssi` |

### Options avancées

| Option | Description |
|--------|-------------|
| `--skip-hardening` | Ignorer l'étape de durcissement |
| `--dry-run` | Mode simulation (aucune modification) |
| `--forest-mode` | Niveau fonctionnel forêt (défaut: WinThreshold) |
| `--domain-mode` | Niveau fonctionnel domaine (défaut: WinThreshold) |
| `-v, --verbose` | Mode verbeux |
| `-h, --help` | Afficher l'aide complète |
| `-V, --version` | Afficher la version |

---

## 💡 Exemples

### Déploiement minimal (lab/test)

```bash
./deploy-ad.sh \
  -t 192.168.1.10 \
  -p 'vagrant' \
  -s 'S@feMode123!'
```

### Déploiement avec domaine personnalisé

```bash
./deploy-ad.sh \
  -t 192.168.1.10 \
  -p 'P@ssw0rd!' \
  -s 'DsrmP@ss!' \
  -d entreprise.local \
  -n ENTREPRISE
```

### Déploiement complet production

```bash
./deploy-ad.sh \
  -t 192.168.1.10 \
  -p 'P@ssw0rd!' \
  -s 'DsrmP@ss!' \
  -d corp.local \
  -n CORP \
  -u 50 \
  -g "IT,RH,Finance,Direction,Commercial" \
  -H anssi \
  -v
```

### Mode simulation (vérification)

```bash
./deploy-ad.sh \
  -t 192.168.1.10 \
  -p 'P@ssw0rd!' \
  -s 'DsrmP@ss!' \
  --dry-run \
  --verbose
```

### Après promotion DC (utiliser compte domaine)

```bash
./deploy-ad.sh \
  -t 192.168.1.10 \
  -p 'DsrmP@ss!' \
  -s 'DsrmP@ss!' \
  -d corp.local \
  -n CORP \
  -a 'CORP\Administrator'
```

---

## 🔒 Niveaux de durcissement

| Mesure | `minimal` | `standard` | `anssi` | `paranoid` |
|--------|:---------:|:----------:|:-------:|:----------:|
| **MDP minimum** | 8 | 12 | 14 | 16 |
| **Historique MDP** | 5 | 12 | 24 | 24 |
| **Verrouillage (tentatives)** | 10 | 5 | 5 | 3 |
| **Forcer NTLMv2** | ❌ | ✅ | ✅ | ✅ |
| **Signature SMB** | ❌ | ✅ | ✅ | ✅ |
| **Protection LSASS** | ❌ | ✅ | ✅ | ✅ |
| **Signature LDAP** | ❌ | ✅ | ✅ | ✅ |

> 💡 **Recommandation :** Utilisez `anssi` pour la production, `minimal` uniquement pour les labs.

---

## 📁 Structure du projet

```
AD-DEPLOYER/
├── ad-deployer/
│   ├── deploy-ad.sh              # Script principal d'orchestration
│   ├── ansible/
│   │   ├── inventory/            # Inventaire généré automatiquement
│   │   └── playbooks/
│   │       ├── 01-prerequisites.yml    # Installation rôles AD-DS, DNS
│   │       ├── 02-create-domain.yml    # Création forêt/domaine
│   │       ├── 03-create-ous.yml       # Structure OUs Tiering
│   │       ├── 04-create-groups.yml    # Groupes de sécurité
│   │       ├── 05-create-users.yml     # Utilisateurs de test
│   │       ├── 06-hardening-anssi.yml  # Durcissement sécurité
│   │       └── 07-create-gpos.yml      # GPOs de sécurité
│   └── logs/                     # Logs d'exécution horodatés
├── README.md
└── LICENSE
```

---

## 🔐 Conformité ANSSI

Ce projet implémente les recommandations de :

- 📘 **[Guide ANSSI PA-099](https://cyber.gouv.fr/publications/recommandations-pour-ladministration-securisee-des-si-reposant-sur-ad)** - Administration sécurisée des SI reposant sur AD
- 📗 **[Points de contrôle AD (CERT-FR)](https://www.cert.ssi.gouv.fr/dur/CERTFR-2020-DUR-001/)** - Durcissement Active Directory

### Mesures appliquées

- 🔐 Politique de mots de passe renforcée (longueur, complexité, historique)
- 🚫 Désactivation des protocoles obsolètes (LM, NTLMv1, SMBv1)
- 🛡️ Isolation des comptes à privilèges (Tiering)
- 📊 Audit et logging renforcés
- 🔒 Protection des credentials (LSASS RunAsPPL)
- ✍️ Signature obligatoire (SMB, LDAP)
- 🖨️ Désactivation Print Spooler sur DC

---

## 📊 Logs

Les logs sont générés dans `logs/` avec horodatage :

```
logs/deploy-ad_2024-12-19_14-30-25.log
```

---

## 🐛 Dépannage

### Erreur "WinRM non accessible"

```bash
# Vérifier la connectivité
nc -zv 192.168.1.10 5985

# Sur Windows, réactiver WinRM
winrm quickconfig -force
```

### Erreur "Credentials rejected" après promotion DC

Après la promotion en DC, le compte local n'existe plus. Utilisez le compte domaine :

```bash
./deploy-ad.sh -t 192.168.1.10 -p 'DsrmP@ss!' -s 'DsrmP@ss!' \
  -d corp.local -n CORP -a 'CORP\Administrator'
```

### Erreur "Collection Ansible manquante"

```bash
ansible-galaxy collection install microsoft.ad community.windows ansible.windows --force
```

### Erreur "Directory object not found"

Les OUs n'existent pas encore. Relancez le script, il exécutera les playbooks dans l'ordre.

### Erreur YAML parsing

Vérifiez qu'il n'y a pas de guillemets manquants dans les playbooks :

```bash
ansible-playbook --syntax-check ansible/playbooks/*.yml
```

---

## 🧪 Environnements testés

| OS | Hyperviseur | Statut |
|----|-------------|--------|
| Windows Server 2022 | Vagrant/VMware | ✅ |
| Windows Server 2019 | Hyper-V | ✅ |
| Windows Server 2019 | VirtualBox | ✅ |

---

## 📜 Licence

Ce projet est sous licence MIT - voir le fichier [LICENSE](LICENSE) pour plus de détails.

---

⭐ **Si ce projet t'a été utile, n'hésite pas à lui donner une étoile !**

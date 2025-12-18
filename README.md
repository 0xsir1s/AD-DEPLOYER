# 🛡️ AD-Deployer - Active Directory Deployment & Hardening Tool

[![Bash](https://img.shields.io/badge/Bash-5.0+-green.svg)](https://www.gnu.org/software/bash/)
[![Ansible](https://img.shields.io/badge/Ansible-2.14+-red.svg)](https://www.ansible.com/)
[![ANSSI](https://img.shields.io/badge/ANSSI-PA--099-blue.svg)](https://cyber.gouv.fr/publications/recommandations-pour-ladministration-securisee-des-si-reposant-sur-ad)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> 🇫🇷 Script Bash orchestrant Ansible pour le déploiement automatisé d'Active Directory avec durcissement selon les recommandations ANSSI.

![AD-Deployer Banner](docs/banner.png)

## 📋 Table des matières

- [Présentation](#-présentation)
- [Fonctionnalités](#-fonctionnalités)
- [Prérequis](#-prérequis)
- [Installation](#-installation)
- [Utilisation](#-utilisation)
- [Architecture](#-architecture)
- [Niveaux de durcissement](#-niveaux-de-durcissement)
- [Recommandations ANSSI](#-recommandations-anssi-implémentées)
- [Exemples](#-exemples)
- [Contribution](#-contribution)
- [Auteur](#-auteur)
- [Références](#-références)

## 🎯 Présentation

**AD-Deployer** est un outil d'automatisation qui simplifie le déploiement d'environnements Active Directory sécurisés. Il combine la puissance de **Bash** pour l'orchestration et **Ansible** pour la configuration, tout en appliquant les **recommandations de sécurité de l'ANSSI** (guide PA-099).

### Pourquoi cet outil ?

- ⏱️ **Gain de temps** : Déploiement complet en quelques minutes
- 🔒 **Sécurité by design** : Durcissement ANSSI intégré dès le départ
- 📚 **Best practices** : Implémentation du modèle de Tiering
- 🔄 **Reproductible** : Infrastructure as Code
- 📝 **Documenté** : Code commenté et documentation complète

## ✨ Fonctionnalités

### Déploiement Active Directory
- ✅ Création de forêt et domaine AD
- ✅ Configuration DNS intégrée
- ✅ Activation de la corbeille AD
- ✅ Configuration des sites AD

### Structure organisationnelle
- ✅ Création automatique des OUs (modèle Tiering)
- ✅ Groupes de sécurité préconfigurés
- ✅ Groupes de délégation
- ✅ Comptes administrateurs par Tier

### Gestion des utilisateurs
- ✅ Création en masse d'utilisateurs
- ✅ Attribution automatique aux groupes
- ✅ Comptes de service (gMSA ready)
- ✅ Mots de passe conformes aux politiques

### Durcissement ANSSI
- ✅ Politique de mots de passe renforcée
- ✅ Désactivation des protocoles obsolètes (LM, NTLMv1)
- ✅ Signature SMB et LDAP obligatoire
- ✅ Protection LSASS (RunAsPPL)
- ✅ Audit avancé configuré
- ✅ GPOs de sécurité prêtes à l'emploi

### GPOs de sécurité
- ✅ Restrictions par Tier (Tier 0, 1, 2)
- ✅ Politique d'audit avancée
- ✅ Central Store ADMX configuré

## 📦 Prérequis

### Contrôleur Ansible (Linux)

```bash
# Système
- Ubuntu 20.04+ / Debian 11+ / CentOS 8+
- Bash 5.0+
- Python 3.8+

# Packages
- ansible >= 2.14
- python3-pip
- sshpass (optionnel)
```

### Serveur cible (Windows)

```
- Windows Server 2016 / 2019 / 2022
- PowerShell 5.1+
- WinRM activé et configuré
- Connectivité réseau (ports 5985/5986)
```

### Collections Ansible requises

```bash
ansible-galaxy collection install microsoft.ad
ansible-galaxy collection install community.windows
ansible-galaxy collection install ansible.windows
```

## 🚀 Installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/DISIZ/ad-deployer.git
cd ad-deployer
```

### 2. Installer les dépendances

```bash
# Sur Ubuntu/Debian
sudo apt update
sudo apt install ansible python3-pip sshpass -y
pip3 install pywinrm

# Collections Ansible
ansible-galaxy collection install microsoft.ad community.windows ansible.windows
```

### 3. Rendre le script exécutable

```bash
chmod +x deploy-ad.sh
```

### 4. Configurer WinRM sur le serveur Windows cible

```powershell
# Sur le serveur Windows (en tant qu'administrateur)
winrm quickconfig -q
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

## 📖 Utilisation

### Syntaxe de base

```bash
./deploy-ad.sh -t <IP_CIBLE> -p <MOT_DE_PASSE> -s <SAFE_MODE_PASSWORD> [OPTIONS]
```

### Options principales

| Option | Description | Défaut |
|--------|-------------|--------|
| `-t, --target` | IP du serveur Windows cible | **Requis** |
| `-p, --password` | Mot de passe administrateur | **Requis** |
| `-s, --safe-mode` | Mot de passe mode récupération | **Requis** |
| `-d, --domain` | Nom du domaine AD | `lab.local` |
| `-n, --netbios` | Nom NetBIOS | Auto-généré |
| `-u, --users` | Nombre d'utilisateurs à créer | `10` |
| `-g, --groups` | Groupes personnalisés (CSV) | - |
| `-H, --hardening` | Niveau de durcissement | `anssi` |
| `-v, --verbose` | Mode verbeux | Désactivé |
| `--dry-run` | Simulation sans exécution | Désactivé |

### Exemple rapide

```bash
# Déploiement minimal
./deploy-ad.sh -t 192.168.1.10 -p 'P@ssw0rd!' -s 'S@feM0de!'

# Déploiement complet avec personnalisation
./deploy-ad.sh \
  --target 192.168.1.10 \
  --password 'P@ssw0rd!' \
  --safe-mode 'S@feM0de!' \
  --domain "entreprise.local" \
  --netbios "ENTREPRISE" \
  --users 50 \
  --groups "IT,RH,Finance,Direction,Commercial" \
  --hardening anssi \
  --verbose
```

## 🏗️ Architecture

```
ad-deployer/
├── deploy-ad.sh                    # Script Bash principal
├── README.md                       # Documentation
├── LICENSE                         # Licence MIT
├── ansible/
│   ├── inventory/
│   │   └── hosts.yml              # Inventaire (généré)
│   ├── group_vars/
│   │   └── all.yml                # Variables (généré)
│   ├── playbooks/
│   │   ├── 01-prerequisites.yml   # Installation rôles Windows
│   │   ├── 02-create-domain.yml   # Création domaine/forêt
│   │   ├── 03-create-ous.yml      # Structure OUs Tiering
│   │   ├── 04-create-groups.yml   # Groupes de sécurité
│   │   ├── 05-create-users.yml    # Comptes utilisateurs
│   │   ├── 06-hardening-anssi.yml # Durcissement ANSSI
│   │   └── 07-create-gpos.yml     # GPOs de sécurité
│   └── templates/                  # Templates Jinja2
├── docs/
│   └── banner.png                 # Image bannière
├── logs/                          # Logs d'exécution
└── scripts/                       # Scripts utilitaires
```

## 🔐 Niveaux de durcissement

| Niveau | Description | Cas d'usage |
|--------|-------------|-------------|
| `minimal` | Configuration de base | Lab, tests |
| `standard` | Bonnes pratiques Microsoft | Environnement interne |
| `anssi` | **Recommandations ANSSI PA-099** | **Production (recommandé)** |
| `paranoid` | Sécurité maximale | Environnement critique |

### Comparatif des mesures

| Mesure | minimal | standard | anssi | paranoid |
|--------|:-------:|:--------:|:-----:|:--------:|
| Longueur MDP minimum | 8 | 12 | 14 | 16 |
| Historique MDP | 5 | 12 | 24 | 24 |
| Verrouillage compte | 10 | 5 | 5 | 3 |
| NTLMv2 uniquement | ❌ | ✅ | ✅ | ✅ |
| Signature SMB | ❌ | ✅ | ✅ | ✅ |
| Protection LSASS | ❌ | ✅ | ✅ | ✅ |
| Credential Guard | ❌ | ❌ | ✅ | ✅ |

## 📜 Recommandations ANSSI implémentées

Ce script implémente les principales recommandations du guide **ANSSI PA-099** :

### Authentification et mots de passe (R1-R5)
- ✅ Politique de complexité des mots de passe
- ✅ Historique et âge des mots de passe
- ✅ Verrouillage des comptes

### Protocoles (R6-R20)
- ✅ R6: Désactivation du stockage LM Hash
- ✅ R7: Configuration LAN Manager (NTLMv2)
- ✅ R9-R10: Restriction énumération anonyme
- ✅ R16-R17: Signature SMB obligatoire
- ✅ R18: Désactivation SMBv1
- ✅ R19-R20: Signature LDAP

### Protection des credentials (R21-R30)
- ✅ R21: Protection LSASS (RunAsPPL)
- ✅ R22: Désactivation WDigest
- ✅ R23: Limitation du cache credentials

### Audit (R41-R50)
- ✅ R41-R50: Audit avancé configuré
- ✅ R46: Taille des journaux augmentée

### Administration (R51-R60)
- ✅ Modèle de Tiering (Tier 0, 1, 2)
- ✅ Séparation des comptes d'administration
- ✅ Groupes Protected Users

## 💡 Exemples

### Déploiement pour un lab de test

```bash
./deploy-ad.sh \
  -t 192.168.56.10 \
  -p 'Test@123!' \
  -s 'Recovery@123!' \
  -d "lab.local" \
  -u 5 \
  -H minimal \
  --verbose
```

### Déploiement production avec durcissement ANSSI

```bash
./deploy-ad.sh \
  -t 10.0.0.10 \
  -p 'Pr0d@SecureP4ss!' \
  -s 'R3c0very@2025!' \
  -d "corp.entreprise.fr" \
  -n "CORP" \
  -u 100 \
  -g "IT,RH,Finance,Direction,Commercial,Production,R&D" \
  -H anssi
```

### Mode simulation (dry-run)

```bash
./deploy-ad.sh \
  -t 192.168.1.10 \
  -p 'P@ssw0rd!' \
  -s 'S@feM0de!' \
  --dry-run \
  --verbose
```

## 🤝 Contribution

Les contributions sont les bienvenues ! N'hésitez pas à :

1. Fork le projet
2. Créer une branche feature (`git checkout -b feature/AmazingFeature`)
3. Commit vos changements (`git commit -m 'Add AmazingFeature'`)
4. Push la branche (`git push origin feature/AmazingFeature`)
5. Ouvrir une Pull Request

## 👤 Auteur

**DISIZ** - Étudiant en Cybersécurité - IPSSI Nice

- 🔗 GitHub: [@DISIZ](https://github.com/DISIZ)
- 💼 LinkedIn: [DISIZ](https://linkedin.com/in/DISIZ)

## 📚 Références

- [Guide ANSSI PA-099 - Administration sécurisée des SI reposant sur AD](https://cyber.gouv.fr/publications/recommandations-pour-ladministration-securisee-des-si-reposant-sur-ad)
- [Points de contrôle Active Directory - CERT-FR](https://www.cert.ssi.gouv.fr/dur/CERTFR-2020-DUR-001/)
- [HardenAD - Projet de durcissement AD](https://github.com/LoicVeirman/HardenAD)
- [Collection Ansible microsoft.ad](https://docs.ansible.com/ansible/latest/collections/microsoft/ad/)
- [Microsoft Security Baselines](https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-security-baselines)

## 📄 Licence

Ce projet est sous licence MIT - voir le fichier [LICENSE](LICENSE) pour plus de détails.

---

<p align="center">
  <i>Projet réalisé dans le cadre du cours de Scripting Bash & Automatisation - IPSSI Nice</i>
</p>

<p align="center">
  ⭐ Si ce projet vous a aidé, n'hésitez pas à lui donner une étoile !
</p>

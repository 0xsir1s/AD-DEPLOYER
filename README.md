# AD-Deployer 🛡️

Déploiement et durcissement automatisé d'Active Directory conforme aux recommandations ANSSI.

## 🚀 Quick Start
```bash
git clone https://github.com/0xsir1s/AD-DEPLOYER.git
cd AD-DEPLOYER
./setup.sh

# Test avec Vagrant (recommandé)
vagrant up && ./test-vagrant.sh

# Ou sur serveur réel
./deploy-ad.sh -d lab.local -n LAB -p 'YourPassword!'
```

✅ **Active Directory déployé en 15 minutes !**

---

## 📋 Description

AD-Deployer est un outil d'automatisation pour le déploiement et la sécurisation d'environnements Active Directory selon le modèle de **Tiering ANSSI** (Administration en Tiers).

### Fonctionnalités principales

- ✅ Déploiement complet d'une forêt/domaine AD
- ✅ Structure OU selon modèle Tiering ANSSI (Tier 0, 1, 2)
- ✅ Création automatisée de groupes de sécurité
- ✅ Génération d'utilisateurs de test
- ✅ Durcissement selon recommandations ANSSI
- ✅ GPOs de sécurité pré-configurées
- ✅ Logging détaillé et gestion d'erreurs

## 🏗️ Architecture
```
Tier 0 (Critique)     → Contrôleurs de domaine, admins domaine
Tier 1 (Serveurs)     → Serveurs applicatifs, admins serveurs  
Tier 2 (Postes)       → Workstations, utilisateurs standards
```

## 🔧 Prérequis

- **OS** : Windows Server 2019/2022
- **RAM** : 4 GB minimum
- **Ansible** : Version 2.9+
- **PowerShell** : Version 5.1+
- **Compte** : Administrateur local

## 🚀 Installation
```bash
git clone https://github.com/0xsir1s/AD-DEPLOYER.git
cd AD-DEPLOYER
chmod +x deploy-ad.sh
```

## 📖 Utilisation

### Déploiement complet
```bash
./deploy-ad.sh --domain lab.local --netbios LAB --password 'P@ssw0rd123!'
```

### Options disponibles
```bash
-d, --domain        Nom FQDN du domaine (ex: lab.local)
-n, --netbios       Nom NetBIOS (ex: LAB)
-p, --password      Mot de passe administrateur
-i, --ip            Adresse IP du DC (optionnel)
-h, --help          Affiche l'aide
--skip-hardening    Passe le durcissement ANSSI
--dry-run           Mode test sans modification
```

### Exemples
```bash
# Déploiement avec IP personnalisée
./deploy-ad.sh -d corp.local -n CORP -p 'SecureP@ss!' -i 192.168.1.10

# Déploiement sans durcissement (test)
./deploy-ad.sh -d test.local -n TEST -p 'Test123!' --skip-hardening
```

## 📁 Structure du projet
```
ad-deployer/
├── deploy-ad.sh              # Script principal orchestration
├── ansible/playbooks/        # Playbooks Ansible modulaires
│   ├── 01-prerequisites.yml
│   ├── 02-create-domain.yml
│   ├── 03-create-ous.yml
│   ├── 04-create-groups.yml
│   ├── 05-create-users.yml
│   ├── 06-hardening-anssi.yml
│   └── 07-create-gpos.yml
├── docs/                     # Documentation technique
└── logs/                     # Logs d'exécution
```

## 🔒 Conformité ANSSI

Ce projet implémente les recommandations de :
- **Guide ANSSI - Administration Sécurisée des SI** (2015)
- **Modèle Tiering Microsoft** adapté au contexte français

### Mesures de sécurité appliquées

- 🔐 Politique de mots de passe renforcée
- 🚫 Désactivation des protocoles legacy (SMBv1, NTLM)
- 🛡️ Isolation des comptes à privilèges
- 📊 Audit et logging renforcés
- 🔄 Restriction des droits d'administration

## 📊 Logs et monitoring

Les logs sont stockés dans `logs/` avec horodatage :
```
logs/deploy-ad_2024-12-19_14-30-25.log
```

## 🧪 Environnement de test

Testé sur :
- Windows Server 2022 (Vagrant/VMware)
- Windows Server 2019 (Hyper-V)
- Domaine : lab.local

## 🤝 Contribution

Les contributions sont les bienvenues ! Merci de :
1. Fork le projet
2. Créer une branche (`git checkout -b feature/amelioration`)
3. Commit (`git commit -m 'Ajout fonctionnalité'`)
4. Push (`git push origin feature/amelioration`)
5. Ouvrir une Pull Request

## 📜 Licence

MIT License - voir fichier [LICENSE](LICENSE)

## ✍️ Auteur

**0xsir1s** - 
- GitHub : [@0xsir1s](https://github.com/0xsir1s)

---

⭐ **N'hésite pas à star le projet si tu le trouves utile !**
```

Et aussi la **LICENSE** corrigée :
```
MIT License

Copyright (c) 2024 0xsir1s

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

# Guide d'Installation AD-Deployer

## 📋 Prérequis détaillés

### Infrastructure

- **OS** : Windows Server 2019/2022 (Standard ou Datacenter)
- **CPU** : 2 vCPUs minimum (4 recommandés)
- **RAM** : 4 GB minimum (8 GB recommandés)
- **Disque** : 60 GB minimum
- **Réseau** : Interface réseau statique configurée

### Logiciels requis

#### Sur la machine de contrôle (Linux/WSL)
```bash
# Ansible
sudo apt update
sudo apt install ansible -y
ansible --version  # Vérifier version >= 2.9

# Python modules
pip install pywinrm
pip install requests

# Git
sudo apt install git -y
```

#### Sur le serveur Windows cible
```powershell
# PowerShell 5.1 (inclus dans Windows Server 2019/2022)
$PSVersionTable.PSVersion

# WinRM (activation pour Ansible)
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# Vérification
Test-WSMan
```

## 🚀 Installation pas à pas

### Étape 1 : Préparer le serveur Windows

#### 1.1 Configuration IP statique
```powershell
# Vérifier les interfaces
Get-NetIPConfiguration

# Configurer IP statique (adapter selon ton réseau)
New-NetIPAddress -InterfaceAlias "Ethernet0" `
    -IPAddress 192.168.1.10 `
    -PrefixLength 24 `
    -DefaultGateway 192.168.1.1

# Configurer DNS (pointer vers lui-même après installation)
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" `
    -ServerAddresses 192.168.1.10
```

#### 1.2 Renommer le serveur
```powershell
Rename-Computer -NewName "DC01" -Restart
```

#### 1.3 Configurer WinRM pour Ansible
```powershell
# Télécharger et exécuter le script de configuration
$url = "https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1"
$file = "$env:temp\ConfigureRemotingForAnsible.ps1"

(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)

powershell.exe -ExecutionPolicy ByPass -File $file

# Vérifier les listeners WinRM
winrm enumerate winrm/config/Listener
```

### Étape 2 : Cloner le projet
```bash
# Sur ta machine de contrôle
cd ~/projects
git clone https://github.com/DISIZ/ad-deployer.git
cd ad-deployer

# Vérifier la structure
tree -L 2
```

### Étape 3 : Configuration Ansible

#### 3.1 Créer l'inventaire
```bash
mkdir -p inventory
nano inventory/hosts.ini
```

Contenu de `hosts.ini` :
```ini
[windows_servers]
dc01 ansible_host=192.168.1.10

[windows_servers:vars]
ansible_user=Administrator
ansible_password=TonMotDePasseActuel
ansible_connection=winrm
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_port=5985
```

#### 3.2 Tester la connexion
```bash
ansible windows_servers -i inventory/hosts.ini -m win_ping
```

**Résultat attendu** :
```json
dc01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

### Étape 4 : Préparer les variables

#### 4.1 Créer le fichier de variables
```bash
nano ansible/vars/domain_config.yml
```

Contenu :
```yaml
---
# Configuration domaine
domain_name: "lab.local"
domain_netbios: "LAB"
domain_mode: "WinThreshold"  # Windows Server 2016+
forest_mode: "WinThreshold"

# Mot de passe admin (DSRM)
safe_mode_password: "P@ssw0rd123!Complex"

# Configuration réseau DC
dc_ip_address: "192.168.1.10"
dc_subnet: "255.255.255.0"
dc_gateway: "192.168.1.1"
dc_dns: "127.0.0.1"

# Options
create_test_users: true
apply_hardening: true
skip_gpo_creation: false
```

#### 4.2 Sécuriser les credentials (optionnel)
```bash
# Créer un vault Ansible
ansible-vault create ansible/vars/secrets.yml

# Y stocker les mots de passe
domain_admin_password: "P@ssw0rd123!Complex"
local_admin_password: "LocalP@ss123!"
```

### Étape 5 : Lancer le déploiement

#### 5.1 Vérification pré-déploiement (dry-run)
```bash
./deploy-ad.sh \
    --domain lab.local \
    --netbios LAB \
    --password 'P@ssw0rd123!Complex' \
    --dry-run
```

#### 5.2 Déploiement complet
```bash
./deploy-ad.sh \
    --domain lab.local \
    --netbios LAB \
    --password 'P@ssw0rd123!Complex' \
    --ip 192.168.1.10
```

**Durée estimée** : 15-25 minutes selon le matériel

#### 5.3 Suivi de l'exécution

Le script affiche :
```
[INFO] 2024-12-19 14:30:15 - Démarrage du déploiement AD
[INFO] 2024-12-19 14:30:16 - Phase 1/7 : Installation prérequis
[OK]   2024-12-19 14:32:45 - Rôles Windows installés
[INFO] 2024-12-19 14:32:46 - Phase 2/7 : Création forêt/domaine
...
```

Les logs complets sont dans `logs/deploy-ad_2024-12-19_14-30-15.log`

## ✅ Vérifications post-installation

### Vérification 1 : Statut du domaine
```powershell
# Se connecter au DC
ssh Administrator@192.168.1.10

# Vérifier la forêt
Get-ADForest

# Vérifier le domaine
Get-ADDomain

# Vérifier les rôles FSMO
netdom query fsmo
```

**Résultat attendu** :
```
Schema master           DC01.lab.local
Domain naming master    DC01.lab.local
PDC                     DC01.lab.local
RID pool manager        DC01.lab.local
Infrastructure master   DC01.lab.local
```

### Vérification 2 : Structure OU
```powershell
# Lister les OUs créées
Get-ADOrganizationalUnit -Filter * | 
    Select-Object Name, DistinguishedName | 
    Sort-Object Name
```

**Doit afficher** :
```
Tier0-Admin
Tier0-Admin/Accounts
Tier0-Admin/Devices
Tier1-Servers
Tier1-Servers/Accounts
...
```

### Vérification 3 : Groupes de sécurité
```powershell
# Lister les groupes T0
Get-ADGroup -Filter "Name -like 'T0-*'" | Select-Object Name

# Vérifier les membres
Get-ADGroupMember -Identity "T0-DomainAdmins"
```

### Vérification 4 : Utilisateurs de test
```powershell
# Lister les utilisateurs créés
Get-ADUser -Filter "Name -like 't*-*'" | 
    Select-Object Name, SamAccountName, Enabled

# Tester l'authentification
$cred = Get-Credential -UserName "LAB\t0-admin01"
Test-ComputerSecureChannel -Credential $cred
```

### Vérification 5 : GPOs
```powershell
# Lister les GPOs
Get-GPO -All | Select-Object DisplayName, GpoStatus

# Vérifier les liens
Get-GPInheritance -Target "OU=Tier0-Admin,DC=lab,DC=local"
```

### Vérification 6 : Services DNS
```powershell
# Vérifier les zones DNS
Get-DnsServerZone

# Tester la résolution
Resolve-DnsName dc01.lab.local
Resolve-DnsName lab.local
```

## 🔧 Configuration post-déploiement

### Ajouter un second DC (recommandé)
```bash
# Utiliser le playbook de réplication
ansible-playbook -i inventory/hosts.ini \
    ansible/playbooks/08-add-secondary-dc.yml \
    -e "secondary_dc_name=DC02" \
    -e "secondary_dc_ip=192.168.1.11"
```

### Joindre des workstations au domaine
```powershell
# Sur le poste Windows à joindre
Add-Computer -DomainName lab.local `
    -Credential LAB\Administrator `
    -OUPath "OU=Computers,OU=Devices,OU=Tier2-Workstations,DC=lab,DC=local" `
    -Restart
```

### Configurer la réplication DNS
```powershell
# Forcer la réplication AD
repadmin /syncall /AdeP
```

## 📊 Monitoring initial

### Vérifier la santé AD
```powershell
# DCDiag complet
dcdiag /v > C:\dcdiag_report.txt

# Vérification rapide
dcdiag /test:DNS /v
dcdiag /test:Replications
```

### Analyser les logs d'installation
```bash
# Sur la machine de contrôle
less logs/deploy-ad_$(date +%Y-%m-%d)*.log

# Rechercher les erreurs
grep -i "error\|failed" logs/*.log
```

## 🐛 Dépannage initial

### Problème : WinRM ne répond pas
```powershell
# Sur le serveur Windows
Get-Service WinRM | Restart-Service
Test-WSMan -ComputerName localhost
```

### Problème : DNS ne résout pas
```powershell
# Vérifier le service DNS
Get-Service DNS | Restart-Service

# Recréer les enregistrements
Register-DnsClient
ipconfig /registerdns
```

### Problème : Échec promotion DC
```powershell
# Vérifier les logs Windows
Get-EventLog -LogName "Directory Service" -Newest 50

# Réessayer la promotion manuellement
Install-ADDSForest -DomainName lab.local -Force
```

## 📚 Prochaines étapes

1. ✅ Domaine déployé
2. → Configurer la sauvegarde AD
3. → Implémenter PAW (Privileged Access Workstations)
4. → Former les administrateurs au modèle Tiering
5. → Déployer les outils de monitoring (Zabbix, ELK)

---

**Support** : Consulter [TROUBLESHOOTING.md](TROUBLESHOOTING.md) pour les problèmes courants.

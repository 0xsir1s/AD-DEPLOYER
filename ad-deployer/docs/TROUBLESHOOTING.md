# Guide de Dépannage AD-Deployer

## 🔍 Diagnostics Rapides

### Vérification de l'état global
```bash
# Sur la machine de contrôle
./deploy-ad.sh --domain lab.local --netbios LAB --password 'Test123!' --dry-run

# Vérifier les logs
tail -f logs/deploy-ad_*.log
```
```powershell
# Sur le DC Windows
# Santé générale
dcdiag /v

# État des services
Get-Service ADWS,DNS,Netlogon,NTDS | Format-Table -AutoSize

# Réplication
repadmin /showrepl
```

## ❌ Problèmes Courants

### 1. Échec de connexion WinRM

#### Symptômes
```
FAILED! => {"msg": "winrm or requests is not installed"}
UNREACHABLE! => {"changed": false, "msg": "ssl: auth method ssl requires..."}
```

#### Diagnostic
```bash
# Tester depuis la machine de contrôle
ansible windows_servers -i inventory/hosts.ini -m win_ping

# Vérifier pywinrm
python3 -c "import winrm; print('OK')"
```

#### Solutions

**Solution 1 : Installer pywinrm**
```bash
pip3 install pywinrm
pip3 install requests
pip3 install requests-ntlm
```

**Solution 2 : Configurer WinRM sur le serveur**
```powershell
# Sur le serveur Windows
Enable-PSRemoting -Force

# Autoriser l'authentification Basic (dev uniquement)
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true

# Autoriser le trafic non chiffré (dev uniquement)
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true

# Configurer TrustedHosts
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# Redémarrer WinRM
Restart-Service WinRM

# Vérifier
Test-WSMan -ComputerName localhost
winrm enumerate winrm/config/Listener
```

**Solution 3 : Pare-feu**
```powershell
# Autoriser WinRM HTTP
New-NetFirewallRule -Name "WinRM-HTTP" -DisplayName "WinRM HTTP" `
    -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985

# Autoriser WinRM HTTPS (production)
New-NetFirewallRule -Name "WinRM-HTTPS" -DisplayName "WinRM HTTPS" `
    -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5986
```

**Solution 4 : Vérifier l'inventaire Ansible**
```ini
# inventory/hosts.ini
[windows_servers]
dc01 ansible_host=192.168.1.10

[windows_servers:vars]
ansible_user=Administrator
ansible_password=VotreMotDePasse
ansible_connection=winrm
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_port=5985
```

### 2. Échec de promotion du contrôleur de domaine

#### Symptômes
```
FAILED! => {"msg": "Failed to install ADDSForest"}
Le serveur doit être redémarré avant de devenir un contrôleur de domaine
```

#### Diagnostic
```powershell
# Vérifier si le rôle AD-Domain-Services est installé
Get-WindowsFeature -Name AD-Domain-Services

# Vérifier les logs d'installation
Get-EventLog -LogName System -Source "Microsoft-Windows-ServerManager" -Newest 20

# Vérifier l'état de la promotion
Get-ADDomainController -Filter * -ErrorAction SilentlyContinue
```

#### Solutions

**Solution 1 : Prérequis manquants**
```powershell
# Installer manuellement les prérequis
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Puis réessayer
Install-ADDSForest `
    -DomainName "lab.local" `
    -DomainNetbiosName "LAB" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force) `
    -InstallDns:$true `
    -Force:$true
```

**Solution 2 : Netlogon en erreur**
```powershell
# Arrêter Netlogon
Stop-Service Netlogon -Force

# Nettoyer
Remove-Item "C:\Windows\SYSVOL" -Recurse -Force -ErrorAction SilentlyContinue

# Réinstaller AD DS
Uninstall-WindowsFeature AD-Domain-Services -Remove
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# Repromoter
Install-ADDSForest -DomainName "lab.local" ...
```

**Solution 3 : Conflit DNS**
```powershell
# Vérifier la configuration DNS
Get-DnsClientServerAddress

# Pointer vers 127.0.0.1 AVANT la promotion
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 127.0.0.1

# Puis repromoter
```

### 3. Problèmes DNS après installation

#### Symptômes
```
ping lab.local → Échec
nslookup dc01.lab.local → Server failed
Les clients ne trouvent pas le domaine
```

#### Diagnostic
```powershell
# Vérifier le service DNS
Get-Service DNS

# Vérifier les zones DNS
Get-DnsServerZone

# Tester la résolution
Resolve-DnsName lab.local
Resolve-DnsName dc01.lab.local
Resolve-DnsName _ldap._tcp.lab.local -Type SRV

# Vérifier les enregistrements SRV
nslookup -type=SRV _ldap._tcp.lab.local
```

#### Solutions

**Solution 1 : Redémarrer DNS**
```powershell
Restart-Service DNS
ipconfig /registerdns
```

**Solution 2 : Recréer les enregistrements**
```powershell
# Forcer l'enregistrement DNS du DC
Register-DnsClient -Force

# Vérifier les enregistrements créés
Get-DnsServerResourceRecord -ZoneName "lab.local" | 
    Where-Object {$_.HostName -like "*dc*"}
```

**Solution 3 : Pointeur DNS incorrect**
```powershell
# Le DC doit pointer vers lui-même
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 127.0.0.1

# Vérifier
Get-DnsClientServerAddress
```

**Solution 4 : Zone DNS corrompue**
```powershell
# Supprimer et recréer la zone (ATTENTION : perte de données)
Remove-DnsServerZone -Name "lab.local" -Force

# Attendre 30 secondes

# Recréer automatiquement
dcdiag /fix
```

### 4. Les OUs ou groupes ne se créent pas

#### Symptômes
```
FAILED! => {"msg": "The specified object already exists"}
Get-ADOrganizationalUnit -Filter * → Liste vide ou incomplète
```

#### Diagnostic
```powershell
# Vérifier les OUs existantes
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName

# Vérifier les groupes
Get-ADGroup -Filter * | Where-Object {$_.Name -like "T*-*"}

# Vérifier les permissions
whoami /all
```

#### Solutions

**Solution 1 : Nettoyer les objets existants**
```powershell
# ATTENTION : supprime TOUTES les OUs personnalisées
Get-ADOrganizationalUnit -Filter "Name -like 'Tier*'" | 
    Set-ADObject -ProtectedFromAccidentalDeletion $false -PassThru | 
    Remove-ADOrganizationalUnit -Confirm:$false -Recursive

# Relancer le playbook
ansible-playbook ansible/playbooks/03-create-ous.yml
```

**Solution 2 : Problème de permissions**
```powershell
# S'assurer d'être dans le groupe Domain Admins
Add-ADGroupMember -Identity "Domain Admins" -Members "Administrator"

# Vérifier
Get-ADGroupMember -Identity "Domain Admins"
```

**Solution 3 : Attendre la réplication**
```powershell
# Forcer la réplication AD
repadmin /syncall /AdeP

# Attendre 30 secondes
Start-Sleep -Seconds 30

# Réessayer
```

### 5. GPOs non appliquées

#### Symptômes
```
gpresult /r → Aucune GPO listée
Get-GPO -All → GPOs créées mais non liées
Les paramètres de sécurité ne sont pas appliqués
```

#### Diagnostic
```powershell
# Lister toutes les GPOs
Get-GPO -All | Select-Object DisplayName, GpoStatus

# Vérifier les liens
Get-GPInheritance -Target "OU=Tier0-Admin,DC=lab,DC=local"

# Forcer une mise à jour
gpupdate /force

# Voir le résultat
gpresult /h C:\gpresult.html
```

#### Solutions

**Solution 1 : Lier manuellement les GPOs**
```powershell
# Lier une GPO à une OU
New-GPLink -Name "T0-PAW-Restrictions" `
    -Target "OU=Tier0-Admin,DC=lab,DC=local" `
    -LinkEnabled Yes

# Vérifier
Get-GPInheritance -Target "OU=Tier0-Admin,DC=lab,DC=local"
```

**Solution 2 : GPO non répliquée**
```powershell
# Forcer la réplication des GPOs
repadmin /syncall /AdeP

# Attendre
Start-Sleep -Seconds 60

# Forcer l'application
gpupdate /force
```

**Solution 3 : Permissions manquantes**
```powershell
# Vérifier les permissions sur la GPO
Get-GPPermission -Name "T0-PAW-Restrictions" -All

# Ajouter "Authenticated Users" en lecture
Set-GPPermission -Name "T0-PAW-Restrictions" `
    -TargetName "Authenticated Users" `
    -TargetType Group `
    -PermissionLevel GpoRead
```

### 6. Utilisateurs ne peuvent pas se connecter

#### Symptômes
```
Échec de connexion : "Le nom d'utilisateur ou mot de passe est incorrect"
Les comptes existent dans AD mais connexion impossible
```

#### Diagnostic
```powershell
# Vérifier si le compte existe
Get-ADUser -Identity "t0-admin01"

# Vérifier l'état du compte
Get-ADUser -Identity "t0-admin01" -Properties Enabled, LockedOut, PasswordExpired

# Vérifier les tentatives de connexion
Get-EventLog -LogName Security -InstanceId 4625 -Newest 10
```

#### Solutions

**Solution 1 : Compte désactivé**
```powershell
# Activer le compte
Enable-ADAccount -Identity "t0-admin01"

# Vérifier
Get-ADUser -Identity "t0-admin01" -Properties Enabled
```

**Solution 2 : Mot de passe expiré**
```powershell
# Réinitialiser le mot de passe
Set-ADAccountPassword -Identity "t0-admin01" `
    -Reset `
    -NewPassword (ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force)

# Forcer le changement au prochain login (optionnel)
Set-ADUser -Identity "t0-admin01" -ChangePasswordAtLogon $false
```

**Solution 3 : Compte verrouillé**
```powershell
# Déverrouiller
Unlock-ADAccount -Identity "t0-admin01"

# Vérifier
Get-ADUser -Identity "t0-admin01" -Properties LockedOut
```

**Solution 4 : SPN dupliqué**
```powershell
# Rechercher les SPN dupliqués
setspn -X

# Si trouvé, supprimer
setspn -D HTTP/dc01 LAB\t0-admin01
```

### 7. Playbook Ansible échoue de manière aléatoire

#### Symptômes
```
FAILED! => {"msg": "Timeout waiting for the WinRM service to become available"}
Parfois ça marche, parfois non
```

#### Solutions

**Solution 1 : Augmenter les timeouts Ansible**
```ini
# ansible/ansible.cfg
[defaults]
timeout = 60

[winrm]
connection_timeout = 60
read_timeout = 90
operation_timeout = 90
```

**Solution 2 : Redémarrages entre playbooks**
```yaml
# Ajouter dans chaque playbook
- name: Attendre la stabilisation
  wait_for_connection:
    timeout: 300
    delay: 10
```

**Solution 3 : Vérifier les ressources**
```powershell
# Sur le DC
Get-Counter '\Memory\Available MBytes'
Get-Counter '\Processor(_Total)\% Processor Time'

# Si RAM < 2GB ou CPU > 90%, augmenter les ressources
```

### 8. Erreur "The specified domain does not exist"

#### Symptômes
```
Get-ADDomain : Impossible de trouver le domaine
Le domaine semble créé mais inaccessible
```

#### Solutions

**Solution 1 : DNS mal configuré**
```powershell
# Vérifier le suffixe DNS
Get-DnsClient | Select-Object InterfaceAlias, ConnectionSpecificSuffix

# Configurer
Set-DnsClient -InterfaceAlias "Ethernet0" -ConnectionSpecificSuffix "lab.local"
```

**Solution 2 : Redémarrer après promotion**
```powershell
# Le serveur DOIT redémarrer après la promotion
Restart-Computer -Force

# Attendre 2-3 minutes puis tester
Get-ADDomain
```

## 📊 Commandes de Diagnostic Avancé

### Logs détaillés
```powershell
# Logs Active Directory
Get-EventLog -LogName "Directory Service" -Newest 50 | Format-Table -AutoSize

# Logs DNS
Get-EventLog -LogName "DNS Server" -Newest 50 | Format-Table -AutoSize

# Logs de sécurité (échecs d'authentification)
Get-EventLog -LogName Security -InstanceId 4625,4771,4776 -Newest 20

# Export complet
dcdiag /v > C:\Temp\dcdiag_full.txt
repadmin /showrepl > C:\Temp\replication.txt
gpresult /h C:\Temp\gpresult.html
```

### Tests de connectivité
```powershell
# Test Kerberos
klist
klist purge
kinit Administrator@LAB.LOCAL

# Test LDAP
Test-ComputerSecureChannel -Verbose

# Test SMB
Get-SmbConnection
Test-NetConnection -ComputerName dc01.lab.local -Port 445

# Test RPC
Test-NetConnection -ComputerName dc01.lab.local -Port 135
```

### Réinitialisation complète (dernier recours)
```powershell
# ATTENTION : Supprime tout le domaine
# Sauvegarder d'abord !

# 1. Rétrograder le DC
Uninstall-ADDSDomainController -Force -DemoteOperationMasterRole:$true

# 2. Redémarrer
Restart-Computer -Force

# 3. Supprimer le rôle
Uninstall-WindowsFeature AD-Domain-Services -Remove

# 4. Nettoyer les résidus
Remove-Item "C:\Windows\SYSVOL" -Recurse -Force
Remove-Item "C:\Windows\NTDS" -Recurse -Force

# 5. Redémarrer
Restart-Computer -Force

# 6. Relancer le déploiement complet
```

## 🆘 Support et Ressources

### Logs du projet
```bash
# Tous les logs
ls -lh logs/

# Dernière exécution
tail -f logs/deploy-ad_$(ls -t logs/ | head -1)

# Rechercher une erreur spécifique
grep -i "failed\|error" logs/*.log
```

### Documentation Microsoft
- [Troubleshooting AD DS](https://docs.microsoft.com/en-us/troubleshoot/windows-server/identity/active-directory-overview)
- [DCDiag Reference](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/cc731968(v=ws.11))
- [Repadmin Reference](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/cc770963(v=ws.11))

---



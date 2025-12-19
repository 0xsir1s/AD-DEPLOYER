# Architecture AD-Deployer

## 🏛️ Modèle Tiering ANSSI

### Vue d'ensemble

Le modèle d'administration en tiers (Tiering) segmente l'infrastructure en 3 niveaux de criticité pour limiter les mouvements latéraux en cas de compromission.
```
┌─────────────────────────────────────────────────────────────┐
│                        TIER 0                                │
│                    (Administration Critique)                 │
│  ┌────────────────────────────────────────────────────┐    │
│  │ - Contrôleurs de domaine (DC)                      │    │
│  │ - Admins Domaine / Entreprise                      │    │
│  │ - Serveurs d'identité (ADFS, PKI)                 │    │
│  │ - Comptes de service privilégiés                   │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            ↓
        ⚠️ Isolation stricte - Pas de connexion descendante
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                        TIER 1                                │
│                   (Administration Serveurs)                  │
│  ┌────────────────────────────────────────────────────┐    │
│  │ - Serveurs applicatifs                             │    │
│  │ - Serveurs de fichiers                             │    │
│  │ - Administrateurs serveurs                         │    │
│  │ - Serveurs de bases de données                     │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            ↓
        ⚠️ Isolation - Administration uniquement vers le bas
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                        TIER 2                                │
│                    (Postes de travail)                       │
│  ┌────────────────────────────────────────────────────┐    │
│  │ - Workstations utilisateurs                        │    │
│  │ - Support technique                                │    │
│  │ - Utilisateurs standards                           │    │
│  │ - Comptes sans privilèges                          │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## 📂 Structure des Unités Organisationnelles (OU)
```
LAB.LOCAL
│
├── Tier0-Admin
│   ├── Accounts                    # Comptes admin T0
│   │   ├── Users                   # Admins domaine
│   │   └── ServiceAccounts         # Comptes de service
│   ├── Devices                     # Équipements T0
│   │   ├── DomainControllers       # DCs
│   │   └── PAW                     # Privileged Access Workstations
│   └── Groups                      # Groupes T0
│       ├── Admins
│       └── ServiceGroups
│
├── Tier1-Servers
│   ├── Accounts                    # Comptes admin serveurs
│   │   ├── Users
│   │   └── ServiceAccounts
│   ├── Devices                     # Serveurs
│   │   ├── ApplicationServers
│   │   ├── FileServers
│   │   └── DatabaseServers
│   └── Groups                      # Groupes T1
│       └── ServerAdmins
│
├── Tier2-Workstations
│   ├── Accounts                    # Comptes utilisateurs
│   │   ├── Users                   # Utilisateurs standards
│   │   └── ServiceAccounts
│   ├── Devices                     # Postes de travail
│   │   ├── Computers
│   │   └── Laptops
│   └── Groups                      # Groupes T2
│       ├── Users
│       └── Support
│
└── Quarantine                      # Zone de quarantaine
    └── NewComputers                # Nouveaux équipements
```

## 🔐 Groupes de Sécurité

### Tier 0 - Critique

| Groupe | Description | Membres par défaut |
|--------|-------------|-------------------|
| `T0-DomainAdmins` | Admins domaine | Administrator |
| `T0-EnterpriseAdmins` | Admins entreprise | Administrator |
| `T0-SchemaAdmins` | Admins schéma | Vide |
| `T0-ServiceAccounts` | Comptes service T0 | Selon besoins |
| `T0-PAW-Users` | Utilisateurs PAW | Admins T0 |

### Tier 1 - Serveurs

| Groupe | Description | Membres par défaut |
|--------|-------------|-------------------|
| `T1-ServerAdmins` | Admins serveurs | Vide |
| `T1-FileServerAdmins` | Admins fichiers | Vide |
| `T1-AppAdmins` | Admins applications | Vide |
| `T1-ServiceAccounts` | Comptes service T1 | Selon besoins |

### Tier 2 - Postes

| Groupe | Description | Membres par défaut |
|--------|-------------|-------------------|
| `T2-Users` | Utilisateurs standards | Domain Users |
| `T2-Support` | Support technique | Vide |
| `T2-WorkstationAdmins` | Admins postes (local) | Vide |
| `T2-ServiceAccounts` | Comptes service T2 | Vide |

## 🛡️ Matrice de Permissions

### Principe : Flux descendant uniquement
```
Tier 0  →  Peut administrer Tier 0, 1, 2
Tier 1  →  Peut administrer Tier 1, 2 (PAS Tier 0)
Tier 2  →  Peut administrer Tier 2 uniquement
```

### Restrictions appliquées

| Depuis | Vers Tier 0 | Vers Tier 1 | Vers Tier 2 |
|--------|-------------|-------------|-------------|
| **Tier 0** | ✅ Admin complet | ✅ Admin complet | ✅ Admin complet |
| **Tier 1** | ❌ Aucun accès | ✅ Admin serveurs | ✅ Admin limité |
| **Tier 2** | ❌ Aucun accès | ❌ Aucun accès | ✅ Accès utilisateur |

## 🔄 Flux d'authentification
```
┌──────────────┐
│ Utilisateur  │
│   T2-User    │
└──────┬───────┘
       │ Authentifie sur
       ↓
┌──────────────┐
│  Workstation │
│   (Tier 2)   │
└──────┬───────┘
       │ Demande ressource
       ↓
┌──────────────┐
│   Serveur    │
│   (Tier 1)   │ ← Gère comptes T1-ServiceAccounts
└──────┬───────┘
       │ Query AD
       ↓
┌──────────────┐
│      DC      │
│   (Tier 0)   │ ← Géré uniquement par T0-Admins
└──────────────┘
```

## 📋 Exemples de Scénarios

### ✅ Scénario AUTORISÉ

**Admin T0 doit redémarrer un serveur applicatif**

1. Admin se connecte sur PAW (Tier 0)
2. Utilise RDP vers serveur T1
3. Exécute tâche administrative
4. ✅ Autorisé : flux descendant T0 → T1

### ❌ Scénario INTERDIT

**Admin T1 doit modifier une GPO domaine**

1. Admin essaie de se connecter au DC
2. GPO "Deny Logon" bloque l'accès
3. ❌ Refusé : flux montant T1 → T0

**Pourquoi ?** Si le poste de l'admin T1 est compromis, l'attaquant ne peut pas escalader vers Tier 0.

### ✅ Scénario CORRECT (alternative)

**Admin T1 nécessite modification GPO**

1. Admin T1 contacte admin T0
2. Admin T0 effectue la modification
3. Ou : Admin T1 utilise PAW T0 avec compte dédié
4. ✅ Respecte l'isolation des tiers

## 🎯 Bénéfices du Modèle

### Limitation des mouvements latéraux

- Compromission d'un poste T2 → Ne peut pas atteindre T0
- Vol de credentials T1 → Inutilisables sur T0
- Malware sur workstation → Isolé au Tier 2

### Traçabilité

- Comptes dédiés par tier
- Logs centralisés par niveau
- Détection d'anomalies facilitée

### Conformité

- ✅ ANSSI - Administration sécurisée
- ✅ ISO 27001 - Ségrégation des accès
- ✅ PCI-DSS - Isolation administrateurs

## 🔧 Implémentation technique

### GPOs principales
```
T0-PAW-Restrictions       → Restrictions connexions T0
T1-Server-Hardening       → Durcissement serveurs T1
T2-Workstation-Baseline   → Baseline sécurité postes
Deny-Tier-Crossing        → Bloque flux montants
```

### Comptes de test générés
```
# Tier 0
t0-admin01@lab.local (Domain Admin)
t0-svc-backup@lab.local (Service)

# Tier 1
t1-admin01@lab.local (Server Admin)
t1-svc-sql@lab.local (Service SQL)

# Tier 2
t2-user01@lab.local (Utilisateur)
t2-support01@lab.local (Support)
```

## 📚 Références

- [ANSSI - Guide d'administration sécurisée](https://www.ssi.gouv.fr/)
- [Microsoft - Privileged Access Workstations](https://docs.microsoft.com/fr-fr/)
- [Active Directory Tiering Model](https://docs.microsoft.com/fr-fr/security/)

---

**Note** : Ce modèle doit être adapté selon la taille et les besoins spécifiques de l'organisation.

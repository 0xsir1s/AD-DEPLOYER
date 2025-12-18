#!/bin/bash

#===============================================================================
#
#          FILE: deploy-ad.sh
#
#         USAGE: ./deploy-ad.sh [OPTIONS]
#
#   DESCRIPTION: Script de déploiement automatisé d'Active Directory avec
#                durcissement selon les recommandations ANSSI.
#                Orchestre des playbooks Ansible pour configurer un environnement
#                AD complet et sécurisé.
#
#       VERSION: 1.1.0
#       CREATED: 2025
#       LICENSE: MIT
#
#   REQUIREMENTS: ansible, python3, pywinrm
#
#   RÉFÉRENCES:
#     - ANSSI PA-099: https://cyber.gouv.fr/publications/recommandations-pour-ladministration-securisee-des-si-reposant-sur-ad
#
#===============================================================================

# Mode strict : arrêt en cas d'erreur, variable non définie, ou échec dans un pipe
set -euo pipefail

#===============================================================================
# VARIABLES GLOBALES
#===============================================================================

# Couleurs pour l'affichage terminal
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Répertoires du projet (relatifs au script)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
readonly INVENTORY_DIR="${ANSIBLE_DIR}/inventory"
readonly PLAYBOOKS_DIR="${ANSIBLE_DIR}/playbooks"
readonly LOGS_DIR="${SCRIPT_DIR}/logs"

# Fichier d'inventaire Ansible (contiendra TOUTES les variables)
readonly INVENTORY_FILE="${INVENTORY_DIR}/hosts.yml"

# Valeurs par défaut pour les options
DEFAULT_DOMAIN="lab.local"
DEFAULT_NETBIOS="LAB"
DEFAULT_USERS=10
DEFAULT_ADMIN="vagrant"
DEFAULT_HARDENING="anssi"
DEFAULT_FOREST_MODE="WinThreshold"
DEFAULT_DOMAIN_MODE="WinThreshold"

# Variables de configuration (définies par les arguments de ligne de commande)
DOMAIN_NAME=""
NETBIOS_NAME=""
ADMIN_USER=""
ADMIN_PASSWORD=""
SAFE_MODE_PASSWORD=""
NUM_USERS=0
GROUPS=""
TARGET_HOST=""
HARDENING_LEVEL=""
FOREST_MODE=""
DOMAIN_MODE=""
VERBOSE=0
DRY_RUN=0
SKIP_HARDENING=0

# Version du script
readonly VERSION="1.1.0"

#===============================================================================
# FONCTIONS D'AFFICHAGE
#===============================================================================

# Affiche la bannière ASCII du projet
show_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
    ___    ____     ____             __                     
   /   |  / __ \   / __ \___  ____  / /___  __  _____  _____
  / /| | / / / /  / / / / _ \/ __ \/ / __ \/ / / / _ \/ ___/
 / ___ |/ /_/ /  / /_/ /  __/ /_/ / / /_/ / /_/ /  __/ /    
/_/  |_/_____/  /_____/\___/ .___/_/\____/\__, /\___/_/     
                          /_/            /____/              
EOF
    echo ""
    echo -e "    ${BOLD}Active Directory Deployment & Hardening Tool${NC}"
    echo -e "    ${CYAN}Basé sur les recommandations ANSSI - v${VERSION}${NC}"
    echo -e "${NC}"
}

# Affiche un message d'information
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Affiche un message de succès
log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

# Affiche un avertissement
log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

# Affiche une erreur (sur stderr)
log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

# Affiche un message de debug (uniquement si --verbose)
log_debug() {
    if [[ ${VERBOSE} -eq 1 ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
    fi
}

# Affiche un titre d'étape encadré
log_step() {
    echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════════${NC}\n"
}

#===============================================================================
# FONCTION D'AIDE
#===============================================================================

# Affiche l'aide complète du script
show_help() {
    cat << EOF
${BOLD}NOM${NC}
    $(basename "$0") - Déploiement automatisé d'Active Directory avec durcissement ANSSI

${BOLD}SYNOPSIS${NC}
    $(basename "$0") -t <IP> -p <PASSWORD> -s <SAFE_MODE_PASSWORD> [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Script de déploiement automatisé d'Active Directory avec durcissement
    selon les recommandations de l'ANSSI (guide PA-099).
    
    Ce script orchestre des playbooks Ansible pour :
    - Installer les rôles AD-DS et DNS sur Windows Server
    - Créer une nouvelle forêt et un domaine Active Directory
    - Configurer la structure des OUs selon le modèle Tiering ANSSI
    - Créer des groupes de sécurité et des utilisateurs
    - Appliquer un durcissement de sécurité selon le niveau choisi
    - Déployer des GPOs de sécurité

${BOLD}OPTIONS REQUISES${NC}
    -t, --target <IP>
        Adresse IP du serveur Windows cible.
        Le serveur doit avoir WinRM activé et accessible.

    -p, --password <PASSWORD>
        Mot de passe du compte administrateur Windows.
        Utilisé pour la connexion WinRM.

    -s, --safe-mode <PASSWORD>
        Mot de passe du mode de récupération Active Directory (DSRM).
        Requis pour la promotion en contrôleur de domaine.

${BOLD}OPTIONS DE CONFIGURATION${NC}
    -d, --domain <DOMAIN>
        Nom DNS complet du domaine Active Directory.
        Défaut: ${DEFAULT_DOMAIN}
        Exemple: entreprise.local, corp.monentreprise.fr

    -n, --netbios <NETBIOS>
        Nom NetBIOS du domaine (max 15 caractères).
        Défaut: généré automatiquement depuis le nom de domaine
        Exemple: ENTREPRISE, CORP

    -a, --admin <USER>
        Nom du compte administrateur pour la connexion WinRM.
        Défaut: ${DEFAULT_ADMIN}

    -u, --users <NUMBER>
        Nombre d'utilisateurs de test à créer.
        Défaut: ${DEFAULT_USERS}
        Les utilisateurs seront nommés user001, user002, etc.

    -g, --groups <GROUPS>
        Liste des groupes métier à créer, séparés par des virgules.
        Exemple: "IT,RH,Finance,Direction,Commercial"
        Ces groupes seront créés en plus des groupes Tiering ANSSI.

${BOLD}OPTIONS DE SÉCURITÉ${NC}
    -H, --hardening <LEVEL>
        Niveau de durcissement de sécurité à appliquer.
        Défaut: ${DEFAULT_HARDENING}
        
        Niveaux disponibles:
          minimal   - Configuration de base, sécurité minimale
                      (Pour labs et tests uniquement)
          standard  - Bonnes pratiques Microsoft
                      (Environnements internes)
          anssi     - Recommandations ANSSI PA-099 [RECOMMANDÉ]
                      (Environnements de production)
          paranoid  - Sécurité maximale
                      (Peut impacter l'utilisabilité)

    --skip-hardening
        Ignorer complètement l'étape de durcissement.
        Utile pour le débogage ou les environnements de test.

    --forest-mode <MODE>
        Niveau fonctionnel de la forêt Active Directory.
        Défaut: ${DEFAULT_FOREST_MODE}
        Valeurs: Win2008, Win2008R2, Win2012, Win2012R2, WinThreshold

    --domain-mode <MODE>
        Niveau fonctionnel du domaine Active Directory.
        Défaut: ${DEFAULT_DOMAIN_MODE}

${BOLD}OPTIONS GÉNÉRALES${NC}
    -v, --verbose
        Active le mode verbeux.
        Affiche les détails des opérations et les commandes Ansible.

    --dry-run
        Mode simulation.
        Génère les fichiers de configuration sans exécuter les playbooks.
        Utile pour vérifier la configuration avant déploiement.

    -h, --help
        Affiche cette aide et quitte.

    -V, --version
        Affiche la version du script et quitte.

${BOLD}EXEMPLES${NC}
    # Déploiement minimal pour un lab
    $(basename "$0") -t 192.168.1.10 -p 'vagrant' -s 'S@feM0de!'

    # Déploiement avec domaine personnalisé
    $(basename "$0") -t 192.168.1.10 -p 'P@ssw0rd!' -s 'S@feM0de!' \\
        --domain "entreprise.local" --netbios "ENTREPRISE"

    # Déploiement complet avec groupes et utilisateurs
    $(basename "$0") -t 192.168.1.10 -p 'P@ssw0rd!' -s 'S@feM0de!' \\
        --domain "corp.local" \\
        --users 50 \\
        --groups "IT,RH,Finance,Direction,Commercial" \\
        --hardening anssi \\
        --verbose

    # Mode simulation pour vérification
    $(basename "$0") -t 192.168.1.10 -p 'P@ssw0rd!' -s 'S@feM0de!' \\
        --dry-run --verbose

${BOLD}PRÉREQUIS${NC}
    Sur la machine de contrôle (Linux) :
    - Ansible 2.14 ou supérieur
    - Python 3.8 ou supérieur
    - Module pywinrm : pip3 install pywinrm
    - Collections Ansible :
        ansible-galaxy collection install microsoft.ad
        ansible-galaxy collection install community.windows
        ansible-galaxy collection install ansible.windows

    Sur le serveur cible (Windows) :
    - Windows Server 2016, 2019 ou 2022
    - WinRM activé et configuré :
        winrm quickconfig -q
        winrm set winrm/config/service '@{AllowUnencrypted="true"}'
        winrm set winrm/config/service/auth '@{Basic="true"}'
    - Connectivité réseau sur le port 5985 (HTTP) ou 5986 (HTTPS)

${BOLD}NIVEAUX DE DURCISSEMENT${NC}
    ┌──────────┬────────────┬──────────┬──────────┬──────────┐
    │ Mesure   │  minimal   │ standard │  anssi   │ paranoid │
    ├──────────┼────────────┼──────────┼──────────┼──────────┤
    │ MDP min  │     8      │    12    │    14    │    16    │
    │ Historiq │     5      │    12    │    24    │    24    │
    │ Verrou   │    10      │     5    │     5    │     3    │
    │ NTLMv2   │    Non     │    Oui   │    Oui   │    Oui   │
    │ SMB Sign │    Non     │    Oui   │    Oui   │    Oui   │
    │ LSASS    │    Non     │    Oui   │    Oui   │    Oui   │
    └──────────┴────────────┴──────────┴──────────┴──────────┘

${BOLD}FICHIERS${NC}
    ansible/inventory/hosts.yml
        Inventaire Ansible généré avec toutes les variables.

    ansible/playbooks/*.yml
        Playbooks de déploiement et configuration.

    logs/
        Répertoire des logs d'exécution.

${BOLD}CODES DE RETOUR${NC}
    0   Succès
    1   Erreur de validation des arguments
    2   Prérequis manquants
    3   Erreur de connectivité
    4   Échec d'un playbook Ansible

${BOLD}AUTEUR${NC}
    DISIZ - Étudiant Cybersécurité IPSSI Nice
    GitHub: https://github.com/DISIZ
    LinkedIn: https://linkedin.com/in/DISIZ

${BOLD}RÉFÉRENCES${NC}
    Guide ANSSI PA-099:
    https://cyber.gouv.fr/publications/recommandations-pour-ladministration-securisee-des-si-reposant-sur-ad

    Points de contrôle AD (CERT-FR):
    https://www.cert.ssi.gouv.fr/dur/CERTFR-2020-DUR-001/

    Projet HardenAD:
    https://github.com/LoicVeirman/HardenAD

${BOLD}VOIR AUSSI${NC}
    ansible-playbook(1), winrm, Active Directory

EOF
}

#===============================================================================
# FONCTIONS DE VALIDATION
#===============================================================================

# Vérifie si une commande existe dans le PATH
command_exists() {
    command -v "$1" &> /dev/null
}

# Vérifie tous les prérequis système
check_prerequisites() {
    log_step "Vérification des prérequis"
    
    local missing_deps=()
    local warnings=()
    
    # Vérification d'Ansible
    if ! command_exists ansible; then
        missing_deps+=("ansible")
    else
        local ansible_version
        ansible_version=$(ansible --version 2>/dev/null | head -n1 | grep -oP '[\d.]+' | head -1 || echo "unknown")
        log_success "Ansible trouvé (version ${ansible_version})"
    fi
    
    # Vérification d'ansible-playbook
    if ! command_exists ansible-playbook; then
        missing_deps+=("ansible-playbook")
    else
        log_success "ansible-playbook trouvé"
    fi
    
    # Vérification de Python
    if ! command_exists python3; then
        missing_deps+=("python3")
    else
        local python_version
        python_version=$(python3 --version 2>/dev/null | grep -oP '[\d.]+' || echo "unknown")
        log_success "Python trouvé (version ${python_version})"
    fi
    
    # Vérification de pip et pywinrm
    if command_exists pip3; then
        if pip3 show pywinrm &> /dev/null; then
            log_success "pywinrm installé"
        else
            warnings+=("pywinrm non installé - Installation: pip3 install pywinrm")
        fi
    else
        warnings+=("pip3 non trouvé")
    fi
    
    # Vérification des collections Ansible
    if command_exists ansible-galaxy; then
        log_info "Vérification des collections Ansible..."
        
        if ansible-galaxy collection list 2>/dev/null | grep -q "microsoft.ad"; then
            log_success "Collection microsoft.ad installée"
        else
            warnings+=("Collection microsoft.ad non installée - ansible-galaxy collection install microsoft.ad")
        fi
        
        if ansible-galaxy collection list 2>/dev/null | grep -q "community.windows"; then
            log_success "Collection community.windows installée"
        else
            warnings+=("Collection community.windows non installée")
        fi
        
        if ansible-galaxy collection list 2>/dev/null | grep -q "ansible.windows"; then
            log_success "Collection ansible.windows installée"
        else
            warnings+=("Collection ansible.windows non installée")
        fi
    fi
    
    # Affichage des avertissements
    for warning in "${warnings[@]:-}"; do
        [[ -n "$warning" ]] && log_warning "$warning"
    done
    
    # Si des dépendances critiques manquent, afficher l'erreur et quitter
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Dépendances manquantes: ${missing_deps[*]}"
        echo ""
        log_info "Installation des dépendances:"
        echo "  sudo apt update && sudo apt install -y ansible python3-pip"
        echo "  pip3 install pywinrm requests-ntlm"
        echo "  ansible-galaxy collection install microsoft.ad community.windows ansible.windows"
        exit 2
    fi
    
    log_success "Tous les prérequis critiques sont satisfaits"
}

# Valide le format d'une adresse IP
validate_ip() {
    local ip=$1
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    # Vérification du format
    if [[ ! $ip =~ $valid_ip_regex ]]; then
        return 1
    fi
    
    # Vérification que chaque octet est <= 255
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done
    
    return 0
}

# Valide le format d'un nom de domaine
validate_domain() {
    local domain=$1
    # Accepte les domaines de type: example.local, sub.example.com, etc.
    local valid_domain_regex='^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    
    if [[ ! $domain =~ $valid_domain_regex ]]; then
        return 1
    fi
    return 0
}

# Valide tous les arguments fournis au script
validate_arguments() {
    log_step "Validation des arguments"
    
    # Vérification des arguments obligatoires
    if [[ -z "${TARGET_HOST}" ]]; then
        log_error "L'adresse IP cible (-t, --target) est obligatoire"
        echo "Utilisez --help pour afficher l'aide"
        exit 1
    fi
    
    if [[ -z "${ADMIN_PASSWORD}" ]]; then
        log_error "Le mot de passe administrateur (-p, --password) est obligatoire"
        exit 1
    fi
    
    if [[ -z "${SAFE_MODE_PASSWORD}" ]]; then
        log_error "Le mot de passe du mode sans échec (-s, --safe-mode) est obligatoire"
        exit 1
    fi
    
    # Validation de l'adresse IP
    if ! validate_ip "${TARGET_HOST}"; then
        log_error "Adresse IP invalide: ${TARGET_HOST}"
        log_info "Format attendu: xxx.xxx.xxx.xxx (exemple: 192.168.1.10)"
        exit 1
    fi
    log_success "Adresse IP valide: ${TARGET_HOST}"
    
    # Validation du nom de domaine
    if ! validate_domain "${DOMAIN_NAME}"; then
        log_error "Nom de domaine invalide: ${DOMAIN_NAME}"
        log_info "Format attendu: example.local, entreprise.com, etc."
        exit 1
    fi
    log_success "Nom de domaine valide: ${DOMAIN_NAME}"
    
    # Validation du nombre d'utilisateurs
    if [[ ! "${NUM_USERS}" =~ ^[0-9]+$ ]] || [[ "${NUM_USERS}" -lt 0 ]]; then
        log_error "Le nombre d'utilisateurs doit être un entier positif ou zéro"
        exit 1
    fi
    log_success "Nombre d'utilisateurs à créer: ${NUM_USERS}"
    
    # Validation du niveau de hardening
    case "${HARDENING_LEVEL}" in
        minimal|standard|anssi|paranoid)
            log_success "Niveau de durcissement: ${HARDENING_LEVEL}"
            ;;
        *)
            log_error "Niveau de durcissement invalide: ${HARDENING_LEVEL}"
            log_info "Niveaux valides: minimal, standard, anssi, paranoid"
            exit 1
            ;;
    esac
    
    # Validation du NetBIOS (max 15 caractères)
    if [[ ${#NETBIOS_NAME} -gt 15 ]]; then
        log_warning "Le nom NetBIOS '${NETBIOS_NAME}' dépasse 15 caractères, il sera tronqué"
        NETBIOS_NAME="${NETBIOS_NAME:0:15}"
    fi
    log_success "Nom NetBIOS: ${NETBIOS_NAME}"
    
    log_success "Tous les arguments sont valides"
}

#===============================================================================
# FONCTIONS DE CONFIGURATION SELON LE NIVEAU DE HARDENING
#===============================================================================

# Ces fonctions retournent les valeurs de configuration selon le niveau choisi
# Basé sur les recommandations ANSSI PA-099

# Longueur minimale des mots de passe
get_password_min_length() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "8" ;;
        standard) echo "12" ;;
        anssi)    echo "14" ;;
        paranoid) echo "16" ;;
    esac
}

# Durée maximale des mots de passe (jours)
get_password_max_age() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "90" ;;
        standard) echo "60" ;;
        anssi)    echo "90" ;;  # ANSSI recommande 1 à 3 mois
        paranoid) echo "30" ;;
    esac
}

# Historique des mots de passe
get_password_history() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "5" ;;
        standard) echo "12" ;;
        anssi)    echo "24" ;;
        paranoid) echo "24" ;;
    esac
}

# Seuil de verrouillage de compte
get_lockout_threshold() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "10" ;;
        standard) echo "5" ;;
        anssi)    echo "5" ;;
        paranoid) echo "3" ;;
    esac
}

# Durée de verrouillage (minutes)
get_lockout_duration() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "15" ;;
        standard) echo "30" ;;
        anssi)    echo "30" ;;
        paranoid) echo "60" ;;
    esac
}

# Signature SMB obligatoire
get_smb_signing() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "false" ;;
        standard) echo "true" ;;
        anssi)    echo "true" ;;
        paranoid) echo "true" ;;
    esac
}

# Signature LDAP obligatoire
get_ldap_signing() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "false" ;;
        standard) echo "true" ;;
        anssi)    echo "true" ;;
        paranoid) echo "true" ;;
    esac
}

# Protection LSASS (RunAsPPL)
get_lsass_protection() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "false" ;;
        standard) echo "true" ;;
        anssi)    echo "true" ;;
        paranoid) echo "true" ;;
    esac
}

#===============================================================================
# GÉNÉRATION DE L'INVENTAIRE ANSIBLE
# IMPORTANT: Toutes les variables sont incluses directement dans l'inventaire
# pour garantir leur chargement par Ansible
#===============================================================================

generate_inventory() {
    log_info "Génération de l'inventaire Ansible..."
    
    # Création des répertoires nécessaires
    mkdir -p "${INVENTORY_DIR}"
    mkdir -p "${LOGS_DIR}"
    
    # Génération de la liste des groupes au format YAML
    local groups_yaml=""
    if [[ -n "${GROUPS}" ]]; then
        groups_yaml="ad_groups:"
        IFS=',' read -ra group_array <<< "${GROUPS}"
        for group in "${group_array[@]}"; do
            group=$(echo "$group" | xargs) # Supprime les espaces
            groups_yaml+=$'\n      - name: "'"${group}"'"'
            groups_yaml+=$'\n        scope: global'
            groups_yaml+=$'\n        category: security'
        done
    else
        groups_yaml="ad_groups: []"
    fi
    
    # Génération de la liste des utilisateurs au format YAML
    local users_yaml=""
    if [[ ${NUM_USERS} -gt 0 ]]; then
        users_yaml="ad_users:"
        for i in $(seq 1 "${NUM_USERS}"); do
            local username="user$(printf '%03d' $i)"
            users_yaml+=$'\n      - username: "'"${username}"'"'
            users_yaml+=$'\n        firstname: "User"'
            users_yaml+=$'\n        lastname: "Number'"${i}"'"'
            users_yaml+=$'\n        password: "U$er'"${i}"'P@ss!"'
            users_yaml+=$'\n        groups:'
            users_yaml+=$'\n          - "Domain Users"'
        done
    else
        users_yaml="ad_users: []"
    fi
    
    # Création du fichier d'inventaire avec TOUTES les variables
    cat > "${INVENTORY_FILE}" << EOF
---
# =============================================================================
# Inventaire Ansible pour AD-Deployer
# Généré automatiquement par deploy-ad.sh v${VERSION}
# Date: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================
# 
# IMPORTANT: Ce fichier contient toutes les variables nécessaires aux playbooks.
# Ne pas modifier manuellement sauf si vous savez ce que vous faites.
#
# =============================================================================

all:
  children:
    # Groupe des contrôleurs de domaine
    domain_controllers:
      hosts:
        dc01:
          ansible_host: ${TARGET_HOST}
          
  vars:
    # =========================================================================
    # CONFIGURATION DE CONNEXION WINRM
    # =========================================================================
    ansible_user: ${ADMIN_USER}
    ansible_password: "${ADMIN_PASSWORD}"
    ansible_connection: winrm
    ansible_winrm_transport: ntlm
    ansible_winrm_server_cert_validation: ignore
    ansible_port: 5985
    
    # =========================================================================
    # CONFIGURATION DU DOMAINE ACTIVE DIRECTORY
    # =========================================================================
    
    # Structure imbriquée pour les playbooks
    ad_domain:
      name: "${DOMAIN_NAME}"
      netbios: "${NETBIOS_NAME}"
      forest_mode: "${FOREST_MODE}"
      domain_mode: "${DOMAIN_MODE}"
      safe_mode_password: "${SAFE_MODE_PASSWORD}"
    
    # Variables individuelles pour compatibilité
    domain_name: "${DOMAIN_NAME}"
    domain_netbios_name: "${NETBIOS_NAME}"
    safe_mode_password: "${SAFE_MODE_PASSWORD}"
    forest_mode: "${FOREST_MODE}"
    domain_mode: "${DOMAIN_MODE}"
    
    # =========================================================================
    # POLITIQUE DE MOTS DE PASSE
    # Configurée selon le niveau de durcissement: ${HARDENING_LEVEL}
    # =========================================================================
    password_policy:
      min_length: $(get_password_min_length)
      complexity_enabled: true
      max_age_days: $(get_password_max_age)
      min_age_days: 1
      history_count: $(get_password_history)
      lockout_threshold: $(get_lockout_threshold)
      lockout_duration_minutes: $(get_lockout_duration)
      lockout_observation_minutes: 30
    
    # =========================================================================
    # CONFIGURATION DE SÉCURITÉ ANSSI
    # Basée sur le guide PA-099
    # =========================================================================
    hardening_level: "${HARDENING_LEVEL}"
    
    anssi_security:
      # Désactivation des protocoles obsolètes
      disable_ntlmv1: true
      disable_lm_hash: true
      disable_anonymous_enumeration: true
      
      # Signature réseau
      smb_signing_required: $(get_smb_signing)
      ldap_signing_required: $(get_ldap_signing)
      
      # Protection des credentials
      credential_guard_enabled: false
      lsass_protection_enabled: $(get_lsass_protection)
      
      # Audit
      audit_policy_enabled: true
      
      # Modèle Tiering
      tiering_enabled: true
    
    # =========================================================================
    # GROUPES DE SÉCURITÉ À CRÉER
    # =========================================================================
    ${groups_yaml}
    
    # =========================================================================
    # UTILISATEURS À CRÉER
    # =========================================================================
    ${users_yaml}
EOF

    log_success "Inventaire généré: ${INVENTORY_FILE}"
    log_debug "Toutes les variables sont incluses dans l'inventaire"
}

#===============================================================================
# FONCTIONS D'EXÉCUTION ANSIBLE
#===============================================================================

# Teste la connectivité réseau et WinRM avec la cible
test_connectivity() {
    log_step "Test de connectivité"
    
    log_info "Test de connexion vers ${TARGET_HOST}..."
    
    # En mode dry-run, on skip les tests
    if [[ ${DRY_RUN} -eq 1 ]]; then
        log_warning "[DRY-RUN] Tests de connectivité ignorés"
        return 0
    fi
    
    # Test ping ICMP
    if ping -c 1 -W 3 "${TARGET_HOST}" &> /dev/null; then
        log_success "Ping ICMP: OK"
    else
        log_warning "Ping ICMP: Échec (peut être bloqué par le firewall)"
    fi
    
    # Test du port WinRM (5985)
    if timeout 5 bash -c "echo > /dev/tcp/${TARGET_HOST}/5985" 2>/dev/null; then
        log_success "Port WinRM (5985): Accessible"
    else
        log_error "Port WinRM (5985): Non accessible"
        echo ""
        log_info "Vérifiez que WinRM est activé sur le serveur Windows:"
        echo "  winrm quickconfig -q"
        echo "  winrm set winrm/config/service '@{AllowUnencrypted=\"true\"}'"
        echo "  winrm set winrm/config/service/auth '@{Basic=\"true\"}'"
        echo ""
        log_info "Vérifiez aussi le pare-feu Windows (port 5985)"
        exit 3
    fi
    
    # Test Ansible win_ping
    log_info "Test de connexion Ansible..."
    if ansible -i "${INVENTORY_FILE}" dc01 -m ansible.windows.win_ping &>/dev/null; then
        log_success "Connexion Ansible: OK"
    else
        log_warning "Test Ansible win_ping: Échec"
        log_info "Le déploiement va quand même être tenté..."
    fi
}

# Exécute un playbook Ansible avec gestion des erreurs
run_playbook() {
    local playbook=$1
    local description=$2
    
    log_info "Exécution: ${description}"
    log_debug "Playbook: ${playbook}"
    
    # En mode dry-run, on n'exécute pas
    if [[ ${DRY_RUN} -eq 1 ]]; then
        log_warning "[DRY-RUN] Simulation: ${playbook}"
        return 0
    fi
    
    # Construction des options Ansible
    local ansible_opts="-i ${INVENTORY_FILE}"
    
    if [[ ${VERBOSE} -eq 1 ]]; then
        ansible_opts+=" -v"
    fi
    
    # Exécution du playbook
    if ansible-playbook ${ansible_opts} "${playbook}"; then
        log_success "${description}: Terminé"
        return 0
    else
        log_error "${description}: Échec"
        return 1
    fi
}

# Exécute tous les playbooks de déploiement dans l'ordre
run_deployment() {
    log_step "Déploiement Active Directory"
    
    local start_time
    start_time=$(date +%s)
    local failed=0
    
    # Étape 1: Installation des prérequis Windows (rôles AD-DS, DNS)
    if [[ -f "${PLAYBOOKS_DIR}/01-prerequisites.yml" ]]; then
        run_playbook "${PLAYBOOKS_DIR}/01-prerequisites.yml" \
            "Installation des prérequis Windows" || failed=1
    else
        log_warning "Playbook 01-prerequisites.yml non trouvé, ignoré"
    fi
    
    # Arrêt si échec critique
    [[ $failed -eq 1 ]] && { log_error "Arrêt du déploiement suite à une erreur"; exit 4; }
    
    # Étape 2: Création du domaine et de la forêt
    if [[ -f "${PLAYBOOKS_DIR}/02-create-domain.yml" ]]; then
        run_playbook "${PLAYBOOKS_DIR}/02-create-domain.yml" \
            "Création du domaine ${DOMAIN_NAME}" || failed=1
    fi
    
    [[ $failed -eq 1 ]] && { log_error "Arrêt du déploiement suite à une erreur"; exit 4; }
    
    # Étape 3: Création des Unités Organisationnelles (OUs)
    if [[ -f "${PLAYBOOKS_DIR}/03-create-ous.yml" ]]; then
        run_playbook "${PLAYBOOKS_DIR}/03-create-ous.yml" \
            "Création des Unités Organisationnelles" || log_warning "Erreur non fatale"
    fi
    
    # Étape 4: Création des groupes de sécurité
    if [[ -f "${PLAYBOOKS_DIR}/04-create-groups.yml" ]]; then
        run_playbook "${PLAYBOOKS_DIR}/04-create-groups.yml" \
            "Création des groupes de sécurité" || log_warning "Erreur non fatale"
    fi
    
    # Étape 5: Création des utilisateurs
    if [[ ${NUM_USERS} -gt 0 ]] && [[ -f "${PLAYBOOKS_DIR}/05-create-users.yml" ]]; then
        run_playbook "${PLAYBOOKS_DIR}/05-create-users.yml" \
            "Création de ${NUM_USERS} utilisateurs" || log_warning "Erreur non fatale"
    fi
    
    # Étape 6: Durcissement ANSSI
    if [[ ${SKIP_HARDENING} -eq 0 ]] && [[ -f "${PLAYBOOKS_DIR}/06-hardening-anssi.yml" ]]; then
        run_playbook "${PLAYBOOKS_DIR}/06-hardening-anssi.yml" \
            "Durcissement ANSSI (niveau: ${HARDENING_LEVEL})" || log_warning "Erreur non fatale"
    elif [[ ${SKIP_HARDENING} -eq 1 ]]; then
        log_warning "Durcissement ignoré (--skip-hardening)"
    fi
    
    # Étape 7: Création des GPOs
    if [[ -f "${PLAYBOOKS_DIR}/07-create-gpos.yml" ]]; then
        run_playbook "${PLAYBOOKS_DIR}/07-create-gpos.yml" \
            "Création et liaison des GPOs" || log_warning "Erreur non fatale"
    fi
    
    # Calcul de la durée
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    log_step "Déploiement terminé"
    log_success "Durée totale: ${minutes} minutes et ${seconds} secondes"
}

#===============================================================================
# FONCTION DE RÉCAPITULATIF
#===============================================================================

# Affiche un récapitulatif de la configuration avant déploiement
show_summary() {
    echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║              RÉCAPITULATIF DE LA CONFIGURATION               ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BOLD}Configuration du domaine:${NC}"
    echo -e "  • Nom du domaine      : ${GREEN}${DOMAIN_NAME}${NC}"
    echo -e "  • Nom NetBIOS         : ${GREEN}${NETBIOS_NAME}${NC}"
    echo -e "  • Mode forêt          : ${GREEN}${FOREST_MODE}${NC}"
    echo -e "  • Mode domaine        : ${GREEN}${DOMAIN_MODE}${NC}"
    echo ""
    
    echo -e "${BOLD}Serveur cible:${NC}"
    echo -e "  • Adresse IP          : ${GREEN}${TARGET_HOST}${NC}"
    echo -e "  • Compte admin        : ${GREEN}${ADMIN_USER}${NC}"
    echo ""
    
    echo -e "${BOLD}Objets à créer:${NC}"
    echo -e "  • Utilisateurs        : ${GREEN}${NUM_USERS}${NC}"
    if [[ -n "${GROUPS}" ]]; then
        echo -e "  • Groupes métier      : ${GREEN}${GROUPS}${NC}"
    else
        echo -e "  • Groupes métier      : ${YELLOW}Aucun (groupes Tiering uniquement)${NC}"
    fi
    echo ""
    
    echo -e "${BOLD}Sécurité:${NC}"
    echo -e "  • Niveau durcissement : ${GREEN}${HARDENING_LEVEL}${NC}"
    echo -e "  • MDP minimum         : ${GREEN}$(get_password_min_length) caractères${NC}"
    echo -e "  • Signature SMB       : ${GREEN}$(get_smb_signing)${NC}"
    echo -e "  • Protection LSASS    : ${GREEN}$(get_lsass_protection)${NC}"
    echo ""
    
    if [[ ${DRY_RUN} -eq 1 ]]; then
        echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  ⚠ MODE SIMULATION - Aucune modification ne sera effectuée   ║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    fi
    
    if [[ ${SKIP_HARDENING} -eq 1 ]]; then
        echo -e "${YELLOW}⚠ Le durcissement sera ignoré (--skip-hardening)${NC}\n"
    fi
}

#===============================================================================
# PARSING DES ARGUMENTS
#===============================================================================

# Parse tous les arguments de la ligne de commande
parse_arguments() {
    # Initialisation avec les valeurs par défaut
    DOMAIN_NAME="${DEFAULT_DOMAIN}"
    NETBIOS_NAME="${DEFAULT_NETBIOS}"
    ADMIN_USER="${DEFAULT_ADMIN}"
    NUM_USERS="${DEFAULT_USERS}"
    HARDENING_LEVEL="${DEFAULT_HARDENING}"
    FOREST_MODE="${DEFAULT_FOREST_MODE}"
    DOMAIN_MODE="${DEFAULT_DOMAIN_MODE}"
    
    # Parsing des arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--target)
                TARGET_HOST="$2"
                shift 2
                ;;
            -d|--domain)
                DOMAIN_NAME="$2"
                # Génération automatique du NetBIOS si pas encore défini
                if [[ "${NETBIOS_NAME}" == "${DEFAULT_NETBIOS}" ]]; then
                    NETBIOS_NAME=$(echo "$2" | cut -d'.' -f1 | tr '[:lower:]' '[:upper:]')
                fi
                shift 2
                ;;
            -n|--netbios)
                NETBIOS_NAME=$(echo "$2" | tr '[:lower:]' '[:upper:]')
                shift 2
                ;;
            -a|--admin)
                ADMIN_USER="$2"
                shift 2
                ;;
            -p|--password)
                ADMIN_PASSWORD="$2"
                shift 2
                ;;
            -s|--safe-mode)
                SAFE_MODE_PASSWORD="$2"
                shift 2
                ;;
            -u|--users)
                NUM_USERS="$2"
                shift 2
                ;;
            -g|--groups)
                GROUPS="$2"
                shift 2
                ;;
            -H|--hardening)
                HARDENING_LEVEL="$2"
                shift 2
                ;;
            --skip-hardening)
                SKIP_HARDENING=1
                shift
                ;;
            --forest-mode)
                FOREST_MODE="$2"
                shift 2
                ;;
            --domain-mode)
                DOMAIN_MODE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -V|--version)
                echo "AD Deployer version ${VERSION}"
                echo "Auteur: DISIZ - IPSSI Nice"
                exit 0
                ;;
            *)
                log_error "Option inconnue: $1"
                echo "Utilisez --help pour afficher l'aide"
                exit 1
                ;;
        esac
    done
}

#===============================================================================
# FONCTION PRINCIPALE
#===============================================================================

main() {
    # Affichage de la bannière
    show_banner
    
    # Parsing des arguments de ligne de commande
    parse_arguments "$@"
    
    # Vérification des prérequis système
    check_prerequisites
    
    # Validation des arguments
    validate_arguments
    
    # Affichage du récapitulatif
    show_summary
    
    # Demande de confirmation (sauf en dry-run)
    if [[ ${DRY_RUN} -eq 0 ]]; then
        echo -e "${YELLOW}Voulez-vous continuer avec cette configuration? [y/N]${NC} "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Opération annulée par l'utilisateur"
            exit 0
        fi
    fi
    
    # Génération de l'inventaire Ansible
    generate_inventory
    
    # Test de connectivité
    test_connectivity
    
    # Exécution du déploiement
    run_deployment
    
    # Message de fin
    echo -e "\n${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}        DÉPLOIEMENT ACTIVE DIRECTORY TERMINÉ AVEC SUCCÈS!        ${NC}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Domaine créé:${NC}           ${DOMAIN_NAME}"
    echo -e "  ${BOLD}Contrôleur de domaine:${NC}  ${TARGET_HOST}"
    echo -e "  ${BOLD}Niveau de sécurité:${NC}     ${HARDENING_LEVEL}"
    echo ""
    echo -e "  ${BOLD}Pour vous connecter:${NC}"
    echo -e "    Utilisateur: ${CYAN}${NETBIOS_NAME}\\Administrator${NC}"
    echo ""
    echo -e "  ${BOLD}Documentation:${NC}"
    echo -e "    ${CYAN}https://cyber.gouv.fr/publications/recommandations-pour-ladministration-securisee-des-si-reposant-sur-ad${NC}"
    echo ""
}

#===============================================================================
# POINT D'ENTRÉE DU SCRIPT
#===============================================================================

# Exécute main() uniquement si le script est appelé directement (pas sourcé)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
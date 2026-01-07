# AD-DEPLOYER v2.1

**Automated, Hardened, and Tiered Active Directory Infrastructure Deployment**

[![License](https://img.shields.io/badge/License-MIT-00b894.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Ansible](https://img.shields.io/badge/Ansible-2.14%2B-ee0000.svg?style=flat-square&logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Windows Server](https://img.shields.io/badge/Windows_Server-2019%2F2022-00a8e8.svg?style=flat-square&logo=windows&logoColor=white)](https://www.microsoft.com/windows-server)
[![Vagrant](https://img.shields.io/badge/Vagrant-Ready-15ddff.svg?style=flat-square&logo=vagrant&logoColor=white)](https://www.vagrantup.com/)
[![ANSSI Compliant](https://img.shields.io/badge/Security-ANSSI%20Hardened-6c5ce7.svg?style=flat-square)](https://cyber.gouv.fr/publications/recommandations-pour-ladministration-securisee-des-si-reposant-sur-ad)

---

## Overview

**AD-DEPLOYER** is an automation engine designed to provision enterprise-grade Active Directory environments.

Built on **Ansible** and **Bash**, it strictly implements the **ANSSI Tiering Model** (PA-099) and enforces rigorous security hardening by default, making it suitable for:
*   Red Team / Blue Team Labs
*   Infrastructure Validation
*   Educational Environments

---

## Key Features

| Feature | Description |
| :--- | :--- |
| **ANSSI Tiering** | Automatic OU structure for **Tier 0** (Identity), **Tier 1** (Servers), and **Tier 2** (Workstations). |
| **Hardening** | Pre-configured policies: `SMB Signing`, `LDAP Signing`, `No NTLMv1`, `LSASS Protection`. |
| **Interactive Wizard** | CLI menu guides through configuration steps. |
| **Infrastructure as Code** | Full **Vagrant** support for 1-click lab instantiation. |
| **Audit & Logging** | Comprehensive logging to `logs/` for post-deployment reviews. |
| **Modular Design** | Granular control via Ansible tags. |

---

## Architecture (Tiering Model)

This tool automatically segments your AD environment to prevent privilege escalation attacks.

```mermaid
graph TD
    T0[Tier 0: Identity Plane] -->|Controls| T1[Tier 1: Application Plane]
    T0 -->|Controls| T2[Tier 2: User Plane]
    T1 -->|Manages| S[Servers]
    T2 -->|Manages| W[Workstations]
    style T0 fill:#fd79a8,stroke:#333,stroke-width:2px,color:black
    style T1 fill:#74b9ff,stroke:#333,stroke-width:2px,color:black
    style T2 fill:#55efc4,stroke:#333,stroke-width:2px,color:black
```

---

## Prerequisites

*   **Linux / WSL** Environment
*   **Ansible** (2.14+)
*   **Python 3** (`pip3 install pywinrm requests-ntlm`)
*   *(Optional)* **Vagrant** + **VirtualBox/VMware**

---

## Getting Started

### Option 1: Vagrant (Automated)
This will create a VM, configure network/WinRM, and deploy AD automatically.
```bash
vagrant up
```

### Option 2: Manual Control
Deploy to an existing Windows Server (e.g., bare metal, ESXi, Hyper-V) accessible via IP.

1.  **Clone Repository**
    ```bash
    git clone https://github.com/0xsir1s/AD-DEPLOYER.git
    cd AD-DEPLOYER/ad-deployer
    ```

2.  **Run Wizard**
    ```bash
    ./deploy-ad.sh
    ```

3.  **Command Line Mode**
    ```bash
    ./deploy-ad.sh -t 192.168.1.50 -d cyber.corp -p 'Admin123!' -s 'SafeMode123!' -H anssi
    ```

---

## Configuration Options

| Flag | Argument | Description |
| :--- | :--- | :--- |
| `-t` | `--target` | IP Address of the target Windows Server. |
| `-d` | `--domain` | FQDN of the new domain (e.g., `lab.local`). |
| `-p` | `--password` | WinRM / Administrator password. |
| `-H` | `--hardening` | Security Level: `minimal`, `standard`, `anssi`, `paranoid`. |
| `-v` | `--verbose` | Enable extensive logging for debugging. |

---

## Project Structure

```text
AD-DEPLOYER/
├── Vagrantfile             # IaC definition
├── README.md               # Documentation
└── ad-deployer/
    ├── deploy-ad.sh        # Main orchestration script
    ├── .gitattributes      # Line-ending enforcer
    ├── logs/               # Log storage
    └── ansible/
        ├── inventory/      # Dynamic inventory
        └── playbooks/
            ├── 01-bootstrap.yml    # Prerequisites
            ├── 02-forest.yml       # Domain Creation
            ├── 03-structure.yml    # OUs & Modeling
            ├── 04-access.yml       # RBAC Groups
            ├── 05-identities.yml   # User Objects
            ├── 06-hardening.yml    # Security Policies
            └── 07-policies.yml     # GPO Enforcement
```

---

## Author

**0xsir1s** (DISIZ)
*   *Cybersecurity Student & Infrastructure Enthusiast*
*   [GitHub](https://github.com/DISIZ)

---

> **Note:** This tool is intended for educational and testing purposes.

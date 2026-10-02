# OPNsense Operations (`opnsense-ops`)

This independent Ansible project manages Day-2 operations, imperative maintenance, configuration backups, and firmware audits for the OPNsense firewall appliance (`26.1.11_10-amd64`).

## Directory Layout

```text
ansible/opnsense-ops/
├── ansible.cfg              # Local project Ansible configuration
├── inventory/
│   ├── hosts.yml            # OPNsense targets and API connection parameters
│   └── group_vars/
│       ├── all.yml          # Global defaults (backup paths, timeouts)
│       └── opnsense.yml     # API credentials mapping
├── playbooks/
│   ├── backup-config.yml    # Exports active /conf/config.xml to local backups
│   └── check-firmware.yml   # Queries available firmware updates safely
├── requirements.yml         # Pinned Ansible Galaxy collections
└── secrets/
    └── README.md            # Guidance for uncommitted credentials
```

## Prerequisites

1. Install project Python dependencies:
   ```bash
   python3 -m pip install -r ../../requirements.txt
   ```
2. Install pinned Galaxy collections:
   ```bash
   ansible-galaxy collection install -r requirements.yml
   ```
3. Ensure service account `svc-ansible-opnsense` is created in OPNsense Web GUI belonging to `grp-ansible-ops`.

## Usage

### 1. Configuration Backup
Export the live configuration XML before maintenance:
```bash
ansible-playbook playbooks/backup-config.yml
```
Backups are saved to `ansible/opnsense-ops/backups/config-<host>-<timestamp>.xml`.

### 2. Firmware Status Check
Check for available updates without applying:
```bash
ansible-playbook playbooks/check-firmware.yml
```

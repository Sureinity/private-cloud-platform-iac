# Zabbix Agent 2 Ansible improvement map

## Purpose

This explanation reviews the current `ansible/infra-ops` `zabbix_agent2` role and identifies what else should be included for a more complete DevOps-grade Zabbix Agent 2 setup. Recommendations are sorted by magnitude: largest operational impact first.

## Current role state

The current role in `ansible/infra-ops/roles/zabbix_agent2` already provides a good base:

- supports Debian-family hosts only, currently Ubuntu and Debian
- asserts the target OS family and supported distribution
- asserts that `zabbix_server_address` is not left as the placeholder `MONITORING_HOST`
- adds the official Zabbix APT repository
- installs `zabbix-agent2`
- creates `/etc/zabbix/zabbix_agent2.d/`
- renders `/etc/zabbix/zabbix_agent2.conf`
- validates the rendered config with `zabbix_agent2 -c %s -T`
- enables and starts `zabbix-agent2`
- restarts the service through a handler when configuration changes

The current inventory targets the PVE host and monolithic Zabbix VM for Agent 2:

```yaml
zabbix-agent2-hosts:
  hosts:
    pve-home:
      ansible_host: 192.0.2.10
      ansible_user: root
    zbx-monolith-server:
      ansible_host: 192.0.2.30
      ansible_user: ubuntu
```

Current group variables set:

```yaml
zabbix_server_address: "192.0.2.30"
zabbix_agent_hostname: "{{ inventory_hostname }}"
zabbix_agent2_supported_distributions:
  - Ubuntu
  - Debian
```

## Recommendations sorted by magnitude

### 1. Define active vs passive monitoring mode explicitly

**Magnitude:** High

The current template enables both:

```ini
Server={{ zabbix_server_address }}
ServerActive={{ zabbix_server_address }}
```

That is workable, but the role should make the intended mode explicit because it changes firewall, Zabbix UI, template, and troubleshooting behavior.

Recommended additions:

- `zabbix_agent2_enable_passive_checks: true`
- `zabbix_agent2_enable_active_checks: true`
- optional `zabbix_agent2_listen_port: 10050`
- optional `zabbix_agent2_server_port: 10051`
- documentation that passive checks require server-to-agent access on TCP `10050`
- documentation that active checks require agent-to-server access on TCP `10051`

Why it matters:

- Zabbix interface availability often stays `Unknown` when passive checks are not reachable or not used.
- Firewall rules and OPNsense policy differ depending on active or passive checks.
- Operators need a predictable answer to whether the server pulls metrics or the agent pushes them.

DevOps principles and competencies:

- **Observability design:** define how telemetry flows before deploying agents.
- **Operational clarity:** reduce ambiguous states such as `Unknown` availability.
- **Network-aware automation:** tie configuration to required firewall paths.

### 2. Add firewall policy handling or explicit firewall documentation

**Magnitude:** High

Agent 2 installation alone is not enough if the Zabbix server cannot reach the agent or the agent cannot reach the server.

Recommended additions:

- document required flows in a how-to page
- optionally manage host firewall rules when a supported firewall is detected
- avoid modifying Proxmox or OPNsense firewall policy inside this role unless that responsibility is intentionally assigned

Required flows:

| Mode | Source | Destination | Port |
|---|---|---|---:|
| Passive checks | Zabbix server | Agent host | TCP `10050` |
| Active checks | Agent host | Zabbix server | TCP `10051` |

For the current PVE topology, the Zabbix server is expected at `192.0.2.30`.

Why it matters:

- Agent service can be healthy while Zabbix still shows the interface as unavailable or unknown.
- Firewalls are often the real failure point in segmented private cloud networks.

DevOps principles and competencies:

- **Systems thinking:** the service, network, firewall, and monitoring server must all align.
- **Least privilege:** allow only the required ports and source/destination addresses.
- **Runbook readiness:** document troubleshooting paths before incidents.

### 3. Add post-install validation tasks

**Magnitude:** High

The role currently validates config syntax before deployment, but it does not prove the service is reachable or accepted by the Zabbix server.

Recommended additions:

- verify service state after start
- verify the agent listens on TCP `10050` when passive checks are enabled
- verify `zabbix_agent2 -t agent.ping` locally
- optionally run a delegated connectivity check from the Zabbix server to the target host
- optionally check recent agent logs for common registration/connectivity failures

Example validation goals:

```text
zabbix-agent2 service is enabled
zabbix-agent2 service is active
local agent test returns agent.ping [s|1]
passive listener exists when passive checks are enabled
Zabbix server can connect to agent:10050 when passive checks are enabled
```

Why it matters:

- A completed Ansible run should prove the operational outcome, not just package installation.
- Fast feedback reduces manual troubleshooting in the Zabbix UI.

DevOps principles and competencies:

- **Shift-left validation:** catch configuration failures during deployment.
- **Automation quality:** include verification, not just mutation.
- **Incident reduction:** reduce unknown monitoring states after rollout.

### 4. Add TLS/PSK support for encrypted agent communication

**Magnitude:** High for non-lab or routed networks; Medium for isolated lab-only networks

The current template intentionally defers transport security. That is fine for a first lab iteration, but the role should eventually support PSK-based encryption.

Recommended additions:

- `zabbix_agent2_tls_enabled: false`
- `zabbix_agent2_tls_connect: psk`
- `zabbix_agent2_tls_accept: psk`
- `zabbix_agent2_tls_psk_identity`
- `zabbix_agent2_tls_psk_file`
- secure PSK file deployment with mode `0600` and owner/group appropriate for the Zabbix agent process
- store PSK values in Ansible Vault or another secret manager, never plaintext inventory

Why it matters:

- Monitoring can expose hostnames, metadata, and operational information.
- If traffic crosses routed, shared, or untrusted segments, plaintext agent communication is undesirable.

DevOps principles and competencies:

- **Security as code:** make secure transport an intentional, repeatable configuration.
- **Secrets management:** keep PSKs out of Git and logs.
- **Defense in depth:** protect telemetry even inside a private cloud when practical.

### 5. Parameterize identity and metadata

**Magnitude:** Medium-high

The current hostname is:

```yaml
zabbix_agent_hostname: "{{ inventory_hostname }}"
```

That is a good default, but the role should support richer identity and metadata for auto-registration and long-term organization.

Recommended additions:

- `zabbix_agent2_hostname`
- `zabbix_agent2_hostname_item`, optionally `system.hostname`
- `zabbix_agent2_host_metadata`
- `zabbix_agent2_host_metadata_item`
- `zabbix_agent2_host_interface_ip`, when later integrating with the Zabbix API
- clear rule that the Zabbix UI host name must match `Hostname` for active checks unless metadata-based auto-registration is used

Why it matters:

- Host identity mismatch is a common reason active checks do not appear.
- Metadata allows auto-registration actions such as assigning groups and templates.

DevOps principles and competencies:

- **Configuration management:** identity should be explicit and reproducible.
- **Scalability:** metadata supports onboarding more hosts without hand-clicking each one.
- **Traceability:** inventory names, Zabbix host names, and UI records should map cleanly.

### 6. Add optional Zabbix API host registration

**Magnitude:** Medium-high

The current role installs the agent, but it does not create or update the corresponding Zabbix host object.

Recommended additions:

- optional play or role for Zabbix API registration, preferably separate from the host-side agent role
- host group assignment
- template assignment
- interface definition for passive checks
- proxy assignment if a proxy is introduced later
- macros for per-host settings

Suggested split:

```text
zabbix_agent2 role: configure the monitored host
zabbix_host_registration role/playbook: configure the Zabbix server object via API
```

Why it matters:

- Installing the agent does not automatically make Zabbix monitor the host unless auto-registration or manual host creation is also done.
- Zabbix UI state should be reproducible, not only manually clicked.

DevOps principles and competencies:

- **Infrastructure as code:** represent monitoring targets declaratively.
- **Separation of concerns:** host configuration and Zabbix server API state are different responsibilities.
- **Reproducibility:** rebuilding Zabbix should not require remembering UI clicks.

### 7. Add repository key integrity controls

**Magnitude:** Medium

The role downloads the official Zabbix repository key with:

```yaml
force: true  # Add checksum later if a published key hash is adopted.
```

Recommended additions:

- pin or verify the repository key fingerprint where practical
- consider a managed dearmored keyring workflow if required by target OS policy
- document package repository trust assumptions
- keep `zabbix_version` intentionally pinned or intentionally current, rather than accidental

Why it matters:

- APT repository trust is a supply-chain boundary.
- For operational automation, package source trust should be auditable.

DevOps principles and competencies:

- **Supply-chain awareness:** verify upstream package trust.
- **Change control:** pin major versions and make upgrades explicit.
- **Auditability:** document why a package source is trusted.

### 8. Add version and upgrade policy

**Magnitude:** Medium

The role defaults to:

```yaml
zabbix_version: "7.0"
```

Recommended additions:

- document supported Zabbix server and agent version compatibility
- decide whether to track LTS or current release
- add a clear upgrade procedure
- optionally allow package state control, for example `present` vs `latest`
- avoid surprise major-version upgrades from inventory defaults

Why it matters:

- Zabbix server, frontend, and agents should remain compatible.
- Package repository version changes can affect future installs.

DevOps principles and competencies:

- **Lifecycle management:** define how versions are upgraded and tested.
- **Release discipline:** avoid implicit major changes.
- **Compatibility management:** keep server and agent assumptions aligned.

### 9. Add plugin and extension configuration support

**Magnitude:** Medium

Agent 2 supports plugin-specific configuration. The role currently creates the include directory but does not manage any include files.

Recommended additions:

- variable-driven drop-in files under `/etc/zabbix/zabbix_agent2.d/`
- Docker plugin access when monitoring Docker hosts
- smartctl/NVMe/sensors support when monitoring physical hosts, if safe and required
- command/UserParameter support only when explicitly needed
- clear allowlist for custom parameters

For the PVE host, useful future checks may include:

- Proxmox host health through system metrics
- disk capacity
- SMART/NVMe health, if tools and permissions are handled safely
- Docker health on Docker hosts

Why it matters:

- Agent 2 becomes more valuable when host-specific capabilities are managed intentionally.
- Custom checks can create security and privilege risks if unmanaged.

DevOps principles and competencies:

- **Observability maturity:** collect meaningful service and host signals, not just basic reachability.
- **Principle of least privilege:** grant agent permissions only for required checks.
- **Maintainability:** keep custom checks declarative and reviewed.

### 10. Add log rotation and retention considerations

**Magnitude:** Medium-low

The template sets:

```ini
LogType=file
LogFile=/var/log/zabbix/zabbix_agent2.log
```

Recommended additions:

- rely on package-provided logrotate when present and document it
- optionally configure `LogFileSize`
- optionally support journald logging through `LogType=system`
- document where to look for agent logs during troubleshooting

Why it matters:

- Monitoring agents should not fill disks with logs.
- Troubleshooting should have a predictable log location.

DevOps principles and competencies:

- **Operational hygiene:** prevent avoidable disk pressure.
- **Troubleshooting competency:** standardize where diagnostics live.

### 11. Add check-mode and idempotency documentation

**Magnitude:** Medium-low

The role is mostly idempotent already, but the README should document expected behavior for dry runs and repeated execution.

Recommended additions:

- expected changed tasks on first run
- expected changed tasks on repeat run
- known check-mode limitations for apt repository and package installation
- validation commands after apply

Why it matters:

- Operators can distinguish real drift from expected first-run changes.
- Check mode becomes a reliable preview step.

DevOps principles and competencies:

- **Idempotency:** repeated automation should converge cleanly.
- **Change safety:** dry-run and diff workflows reduce surprise.
- **Operational predictability:** expected output is documented.

### 12. Add Molecule or lightweight role tests

**Magnitude:** Medium-low for private cloud; higher for team use

Recommended additions:

- `ansible-playbook --syntax-check` in routine validation
- `ansible-lint` where available
- Molecule scenario for Debian and Ubuntu if local containers or VMs are available
- template render checks for passive-only, active-only, and TLS-enabled variants

Why it matters:

- Small roles tend to grow into production-impacting automation.
- Testing catches regressions in templates, variables, and handlers.

DevOps principles and competencies:

- **Continuous validation:** catch defects before live hosts.
- **Testability:** encode assumptions as tests.
- **Quality engineering:** make automation safe to change.

## Suggested implementation order

For this repository, implement in this order:

1. Add explicit active/passive mode variables and documentation.
2. Add post-install validation tasks for service status, local `agent.ping`, and passive listener checks.
3. Add firewall flow documentation for On-Premises PVE and OPNsense LAN assumptions.
4. Add identity and metadata variables for future auto-registration.
5. Add TLS/PSK support using vaulted secrets.
6. Add a separate Zabbix API registration role or playbook.
7. Add repository key fingerprint/checksum policy.
8. Add plugin drop-in support for Docker and PVE host-specific monitoring.
9. Add role tests and stronger CI-style validation.

## Key design principle

Keep the role boundaries clear:

```text
zabbix_agent2 role
  installs and configures the agent on a monitored host

zabbix_host_registration role or playbook
  creates and maintains host objects, host groups, templates, interfaces, and macros in Zabbix

network/firewall automation
  manages OPNsense, host firewall, or Proxmox firewall rules where explicitly owned
```

This separation keeps the agent role safe, idempotent, and reusable while still allowing the broader monitoring system to become fully automated over time.

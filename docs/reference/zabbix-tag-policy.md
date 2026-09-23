# Zabbix tag policy

## Purpose

This policy defines the standard tags used to classify Zabbix monitoring objects, problem events, dashboards, alert actions, reports, and maintenance windows. It is intentionally written like a small professional monitoring standard so this private cloud can practice enterprise-style observability habits without adding unnecessary process overhead.

The policy is documentation-only in this phase. It does not require Ansible, Terraform, Zabbix API automation, or live server mutation.

## Scope

This policy applies to Zabbix objects that are created or maintained for the private cloud monitoring environment, including:

- Hosts
- Templates
- Items and item prototypes
- Triggers and trigger prototypes
- Low-level discovery rules
- Services and service trees
- Dashboards, reports, alert actions, and maintenance windows that filter or route by tags

Tags should describe operational meaning. Host groups should still describe inventory structure.

## Governance model

Use this policy as the source of truth when adding or changing Zabbix tags.

- Tag names and core values are controlled vocabulary.
- New values are allowed when they are documented before or during the change that introduces them.
- Avoid creating synonyms for the same meaning.
- Review tag usage when adding a new host, template, trigger set, alert action, dashboard, or maintenance rule.
- Perform a tag drift review at least quarterly or after major monitoring changes.

Exceptions are allowed, but each exception should have:

- The object or tag affected
- The reason for the exception
- The owner responsible for follow-up
- A review date
- The intended remediation or acceptance decision

## Required tags

The following tags are required for professionally managed hosts and templates. Triggers, items, discovery prototypes, dashboards, actions, and maintenance windows should use the relevant subset that helps filtering, routing, or suppression.

| Tag | Example values | Purpose |
| --- | --- | --- |
| `environment` | `home`, `lab`, `prod-like`, `test` | Separates operating context and alert urgency. |
| `site` | `onprem-pve`, `home-edge`, `ags` | Identifies the physical or logical location. |
| `service` | `virtualization`, `zabbix`, `containers`, `network-edge` | Identifies the monitored service or capability. |
| `component` | `host`, `agent`, `storage`, `cpu`, `memory`, `firewall` | Identifies the affected technical component. |
| `owner` | `infraops`, `network`, `systems` | Identifies who owns review and response. |
| `criticality` | `low`, `medium`, `high`, `critical` | Guides notification urgency and dashboard filtering. |
| `lifecycle` | `experimental`, `active`, `maintenance`, `deprecated`, `retired` | Identifies operational state and expected response. |

## Optional tags

Use optional tags when they improve routing, reporting, maintenance scoping, or service ownership.

| Tag | Example values | Purpose |
| --- | --- | --- |
| `platform` | `proxmox`, `ubuntu`, `debian`, `docker`, `opnsense`, `zabbix` | Identifies the underlying platform or product. |
| `team` | `infraops`, `network`, `platform` | Supports team-level ownership where `owner` is not enough. |
| `maintenance_scope` | `agent`, `docker`, `pve-network`, `firewall`, `storage` | Supports narrow maintenance suppression. |
| `network_zone` | `management`, `lan`, `wan`, `dmz`, `vpn` | Identifies network placement or exposure class. |
| `data_classification` | `public`, `internal`, `sensitive` | Identifies information sensitivity at a high level. |
| `support_tier` | `best-effort`, `standard`, `priority` | Defines expected response posture. |
| `dependency_role` | `upstream`, `downstream`, `standalone` | Helps reason about service dependencies and correlation. |

Do not add precise secrets, credentials, personal data, private topology details, or private key material to any tag value.

## Naming rules

- Use lowercase tag names.
- Use `snake_case` for tag names, such as `maintenance_scope`.
- Use lowercase tag values.
- Use `kebab-case` for multi-word tag values, such as `network-edge`.
- Prefer singular tag names, such as `service`, not `services`.
- Keep tag values stable once alert actions, dashboards, or maintenance rules depend on them.
- Do not use multiple tag names for the same concept.
- Do not overload one tag with multiple meanings.

Good examples:

```text
environment: home
service: zabbix
component: agent
maintenance_scope: zabbix-agent
support_tier: best-effort
```

Avoid:

```text
Environment: Home
service_name: zabbix
services: zabbix-agent
maintenance-scope: Zabbix Agent
```

## Object placement rules

### Hosts

Hosts should carry broad ownership and context tags:

```text
environment: home
site: onprem-pve
owner: infraops
criticality: high
lifecycle: active
platform: proxmox
```

### Templates

Templates should carry reusable platform, service, and component meaning:

```text
service: zabbix
component: agent
platform: ubuntu
```

Template tags are preferred when every host using the template should inherit the same classification.

### Items and triggers

Items and triggers should describe the event or metric meaning:

```text
service: virtualization
component: storage
criticality: high
maintenance_scope: storage
```

Use trigger tags for alert routing, problem filtering, and maintenance rules. Avoid tagging every item manually when a template or discovery prototype can apply the same classification consistently.

### Discovery rules and prototypes

Discovery rules and prototypes should apply tags that will remain useful on discovered entities:

```text
service: containers
component: filesystem
maintenance_scope: docker
```

This is important for filesystems, network interfaces, containers, and other objects that appear dynamically.

### Actions, dashboards, and maintenance windows

Actions, dashboards, reports, and maintenance windows should consume standard tags from this policy. They should not invent new tag names as one-off filters.

Use narrow filters where possible. Prefer maintenance on:

```text
maintenance_scope: docker
```

over suppressing all alerts for a host when only Docker maintenance is planned.

## Criticality definitions

| Value | Meaning | Expected posture |
| --- | --- | --- |
| `low` | Non-urgent or informational issue. | Review during routine maintenance. |
| `medium` | Degraded behavior with limited impact. | Investigate when practical. |
| `high` | Significant service risk or important dependency affected. | Prioritize response. |
| `critical` | Outage, data-loss risk, security exposure, or major dependency failure. | Respond immediately when reachable. |

Criticality should describe operational importance, not just Zabbix trigger severity. A low-severity trigger on a critical service may still carry `criticality: high`.

## Lifecycle definitions

| Value | Meaning |
| --- | --- |
| `experimental` | Temporary or learning object; alerting may be relaxed. |
| `active` | Current supported object; normal alerting applies. |
| `maintenance` | Temporarily undergoing planned work. |
| `deprecated` | Still present but planned for removal or replacement. |
| `retired` | No longer operational; should not produce normal alerts. |

## Example tag sets

### Proxmox virtualization host

```text
environment: home
site: onprem-pve
service: virtualization
component: host
owner: infraops
criticality: high
lifecycle: active
platform: proxmox
support_tier: best-effort
```

### Zabbix Agent 2 monitoring

```text
environment: home
site: onprem-pve
service: zabbix
component: agent
owner: infraops
criticality: medium
lifecycle: active
platform: ubuntu
```

### Network edge firewall

```text
environment: home
site: home-edge
service: network-edge
component: firewall
owner: network
criticality: critical
lifecycle: active
platform: opnsense
network_zone: management
```

### Docker runtime monitoring

```text
environment: home
site: onprem-pve
service: containers
component: runtime
owner: infraops
criticality: medium
lifecycle: active
platform: docker
maintenance_scope: docker
```

## Review checklist

Use this checklist before relying on tags for routing, reporting, or suppression:

- Required tags exist on managed hosts and templates.
- Tag names match this policy exactly.
- Tag values use approved vocabulary or have been documented as new values.
- Actions and maintenance windows filter on the narrowest useful tag set.
- Dashboards and problem views return the expected objects.
- Tags do not contain secrets, credentials, personal data, or sensitive topology details.
- Exceptions have an owner, reason, review date, and remediation path.

## Future automation contract

Future automation may represent tags as a simple mapping:

```yaml
zabbix_tags:
  environment: home
  site: onprem-pve
  service: virtualization
  component: host
  owner: infraops
  criticality: high
  lifecycle: active
  platform: proxmox
```

This repository does not implement that automation yet. Any later automation must preserve this policy as the source of truth and must avoid committing Zabbix API tokens, passwords, or exported secrets.

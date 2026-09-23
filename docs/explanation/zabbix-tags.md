# Zabbix tags and how to use them

Zabbix tags are key-value metadata attached to monitored objects and events. They are one of the most useful ways to make a Zabbix installation easier to search, filter, route, suppress, and report on as the environment grows.

## What tags are

A tag is usually written as a pair:

```text
component: database
environment: production
service: monitoring
site: home-lab
owner: infraops
```

In Zabbix, tags can be added at several levels, including templates, hosts, items, triggers, low-level discovery rules, and event-related configuration. Tags inherited from templates or discovered entities help avoid repeating the same classification manually on every trigger.

The practical idea is simple: instead of relying only on host names or groups, tags describe what a problem, metric, or host means operationally.

For the formal standard used by this repository, see [Zabbix tag policy](../reference/zabbix-tag-policy.md). For the manual operating procedure, see [Apply the Zabbix tag policy](../how-to/apply-zabbix-tag-policy.md). This page explains the concepts; the policy page is the source of truth for approved tag names, values, and governance.


## Why tags matter

Tags are useful because they let operators answer questions like:

- Which alerts affect the `zabbix` service?
- Which problems belong to `environment: lab` rather than production?
- Which alerts should notify the infrastructure owner?
- Which maintenance window should suppress Docker-related checks?
- Which dashboard widgets should show only network or storage issues?

Good tags reduce noisy alerting and make Zabbix easier to operate without changing item keys, trigger names, or host group structure.

## Common tag use cases

### Filtering problems and dashboards

Use tags in problem views, dashboards, reports, and maps to focus on a slice of infrastructure.

Examples:

```text
environment: home
site: pve
service: zabbix
component: agent
criticality: high
lifecycle: active
```

This is especially helpful when a single Zabbix server monitors mixed systems such as Proxmox hosts, VMs, containers, Docker services, firewalls, and endpoints.

### Action routing and notifications

Tags can drive alert actions. For example:

- Send `service: zabbix` alerts to the monitoring maintainer.
- Send `component: storage` alerts with higher urgency.
- Suppress or downgrade `environment: lab` notifications.
- Route `owner: network` alerts separately from `owner: systems` alerts.

This avoids creating too many host groups just for notification logic.

### Maintenance and suppression

Tags can identify which problems should be suppressed during planned work.

Examples:

```text
maintenance_scope: docker
maintenance_scope: zabbix-agent
maintenance_scope: pve-network
```

For a home Proxmox environment, this is safer than broad maintenance windows that hide unrelated failures.

### Event correlation

Tags help correlate related problems. For example, if several triggers share:

```text
service: opnsense
site: home-edge
```

Zabbix can make it easier to reason about whether multiple alerts are part of the same operational incident.

### Permissions and responsibility boundaries

In larger setups, tags can support responsibility boundaries by labeling alerts with an owner, application, environment, or customer. Even in a private cloud, using `owner`, `service`, and `environment` tags keeps future automation easier.

## Suggested tag taxonomy for this repository

Use a small, consistent vocabulary first. Too many ad hoc tag names make filtering harder.

Recommended baseline tags:

| Tag | Example values | Purpose |
| --- | --- | --- |
| `environment` | `home`, `lab`, `prod-like` | Separates operating context and alert urgency. |
| `site` | `onprem-pve`, `ags` | Identifies physical or logical location. |
| `platform` | `proxmox`, `ubuntu`, `docker`, `opnsense` | Identifies the underlying platform. |
| `service` | `zabbix`, `docker`, `networking`, `dns`, `vpn` | Identifies the user-facing or operator-facing service. |
| `component` | `agent`, `server`, `database`, `storage`, `network`, `cpu`, `memory` | Identifies the affected technical component. |
| `owner` | `infraops`, `network`, `systems` | Supports alert routing and responsibility. |
| `criticality` | `low`, `medium`, `high`, `critical` | Helps notification and dashboard filtering. |
| `lifecycle` | `experimental`, `active`, `maintenance`, `deprecated`, `retired` | Identifies operational state. |
| `managed_by` | `ansible`, `terraform`, `manual` | Optional future automation hint showing how the object is expected to be changed. |

For this on-premises PVE repository, start with conservative values such as:

```text
environment: home
site: onprem-pve
owner: infraops
managed_by: ansible
```

Then add service/component tags where they help with filtering or alerting.

## Practical tagging examples

### Zabbix agent host

For a VM monitored by Zabbix Agent 2:

```text
environment: home
site: onprem-pve
platform: ubuntu
service: zabbix-agent
component: agent
owner: infraops
criticality: medium
lifecycle: active
```

### Docker host

For a host running Docker workloads:

```text
environment: home
site: onprem-pve
platform: docker
service: containers
component: runtime
owner: infraops
criticality: medium
lifecycle: active
```

### OPNsense firewall monitoring

For firewall-related hosts, triggers, or templates:

```text
environment: home
site: home-edge
platform: opnsense
service: network-edge
component: firewall
owner: network
criticality: high
lifecycle: active
```

### Proxmox storage trigger

For a storage capacity trigger:

```text
environment: home
site: onprem-pve
platform: proxmox
service: virtualization
component: storage
criticality: high
lifecycle: active
```

## How to apply tags in Zabbix

The exact UI varies by Zabbix version, but the usual workflow is:

1. Open the host, template, item, trigger, or discovery rule you want to classify.
2. Find the **Tags** section.
3. Add a tag name and value.
4. Save the object.
5. Confirm the tag appears in problem filters or event details after the relevant trigger fires.

Prefer adding common tags to templates instead of individual triggers when the tag should apply everywhere that template is used.

## Operational guidance

- Keep tag names lowercase and stable.
- Use `snake_case` for tag names and lowercase `kebab-case` for multi-word values.
- Prefer singular names: `service`, not `services`.
- Prefer predictable values: `onprem-pve`, not sometimes `pve-home` and sometimes `private cloud`.
- Do not store secrets, credentials, exact private topology details, or sensitive personal data in tags.
- Avoid using tags as a substitute for good host groups; use both. Host groups describe inventory structure, while tags describe alert and metric meaning.
- Review tags when adding new templates, hosts, alert actions, or maintenance windows.

## Validation checklist

After introducing or changing tags:

1. Trigger or inspect a known problem event.
2. Confirm inherited and explicit tags appear as expected.
3. Test problem filters by `environment`, `service`, and `component`.
4. Confirm alert actions match only the intended tags.
5. Confirm maintenance rules do not suppress unrelated problems.

## Rollback

If a tag causes noisy routing or hides alerts unexpectedly:

1. Disable or narrow the action, correlation rule, or maintenance rule that uses the tag.
2. Remove or correct the tag on the template, host, trigger, or discovery rule.
3. Re-check the problem view and recent events.
4. Prefer narrowing tag-based rules before deleting tags globally.

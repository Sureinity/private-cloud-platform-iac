# Apply the Zabbix tag policy

## Purpose

Use this guide to apply the repository's Zabbix tag policy to monitored objects in the Zabbix UI. This is a manual operating procedure for practicing professional tag governance in the private cloud.

The source of truth for allowed tag names, required tags, optional tags, and naming rules is [Zabbix tag policy](../reference/zabbix-tag-policy.md).

## Prerequisites

- Access to the Zabbix frontend with permission to edit the target object.
- A known monitored object, such as a host, template, trigger, item, discovery rule, or maintenance window.
- The intended service owner and operational criticality.
- A maintenance or change window if the tag update will affect alert routing or suppression.

This procedure should not require shell access, Ansible, Terraform, or direct database access.

## Safety profile

Applying tags is usually low risk, but tags can affect alert routing, dashboards, reports, event correlation, and maintenance suppression. Treat changes as operationally significant when actions or maintenance windows already depend on tag filters.

Do not put secrets, credentials, personal data, private keys, or sensitive topology details in tag values.

## Tag a host

1. Open the Zabbix frontend.
2. Navigate to the host configuration page.
3. Open the target host.
4. Find the host **Tags** section.
5. Add the required host-level tags:

   ```text
   environment: home
   site: onprem-pve
   service: virtualization
   component: host
   owner: infraops
   criticality: high
   lifecycle: active
   ```

6. Add optional tags only when useful, for example:

   ```text
   platform: proxmox
   support_tier: best-effort
   network_zone: management
   ```

7. Save the host.
8. Reopen or inspect the host and confirm the tags were saved exactly as intended.

## Tag a template

1. Open the target template.
2. Add tags that should be inherited by every host using the template.
3. Prefer service, component, and platform tags:

   ```text
   service: zabbix
   component: agent
   platform: ubuntu
   ```

4. Avoid host-specific values on templates unless every linked host truly shares them.
5. Save the template.
6. Check one linked host or problem event to confirm inherited tags appear as expected.

## Tag a trigger or item

1. Open the item, trigger, item prototype, or trigger prototype.
2. Add tags that describe the event or metric meaning.
3. For alerting, prioritize:

   ```text
   service: containers
   component: runtime
   criticality: medium
   maintenance_scope: docker
   ```

4. Save the object.
5. Confirm future problem events include the expected event tags.

Use prototypes for dynamic objects such as filesystems, network interfaces, or containers so discovered entities receive consistent tags.

## Use tags in alert actions

1. Open the alert action configuration.
2. Add tag-based conditions using only policy-approved tag names and values.
3. Keep routing rules narrow and readable.

Examples:

| Condition | Intended result |
| --- | --- |
| `criticality = critical` | Send urgent notification. |
| `owner = network` | Route to the network owner. |
| `service = network-edge` | Use network-edge escalation language. |
| `lifecycle = experimental` | Lower notification urgency or exclude from paging. |

After editing an action, review recent problem events to make sure the rule would match only the intended scope.

## Use tags in maintenance windows

1. Open or create the maintenance window.
2. Prefer specific service or maintenance-scope filters over broad host suppression.
3. Use a narrow tag such as:

   ```text
   maintenance_scope: docker
   ```

4. Avoid suppressing an entire host when only one subsystem is under maintenance.
5. After the maintenance window starts, confirm unrelated problems are not suppressed.

## Validate tags after a change

After adding or changing tags:

1. Open the problem view and filter by one of the changed tags.
2. Inspect a relevant event and confirm inherited and explicit tags appear as expected.
3. Confirm dashboards and reports still show the intended objects.
4. Confirm alert actions match the intended events only.
5. Confirm maintenance windows do not suppress unrelated alerts.

## Onboard a new monitored object

For each new host, template, or major trigger set:

1. Identify the service and component.
2. Assign an owner.
3. Choose criticality and lifecycle values.
4. Apply required tags from the policy.
5. Add optional tags only when they will be used for filtering, routing, reporting, or maintenance.
6. Validate in the Zabbix problem/event views.
7. Document any new tag value in the policy before relying on it operationally.

## Request a new tag or value

Before adding a new tag name or value:

1. Check whether an existing policy tag already expresses the same meaning.
2. Prefer adding a new value to an existing tag over creating a new tag name.
3. Document the new value in the policy with its purpose.
4. Update any affected dashboards, actions, reports, or maintenance rules.
5. Validate that old filters still work or intentionally migrate them.

## Rollback

If a tag change causes incorrect routing, noisy alerts, missing dashboards, or unintended suppression:

1. Disable or narrow the action, dashboard filter, report, or maintenance window that consumes the tag.
2. Restore the previous tag value on the affected object.
3. Confirm problem/event views return to the expected scope.
4. Record the failed tag value or rule as an exception or policy update if it revealed an ambiguity.

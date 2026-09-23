# Reusable Terraform module: usb_resource_mapping

Manage cluster-wide Proxmox VE USB hardware device mappings using the `bpg/proxmox` provider (`proxmox_hardware_mapping_usb`).

## Purpose

Proxmox VE allows physical USB devices connected to cluster nodes to be mapped to symbolic names (hardware mappings). These named mappings can then be referenced by VMs for USB passthrough without hardcoding node-specific bus/device IDs inside individual VM configurations.

## Status

This module is a reusable component in `terraform/modules/usb_resource_mapping/`. It is maintained in the module catalog but is currently not instantiated in `terraform/live/onprem-pve/main.tf` because active VMs in this environment do not currently require USB hardware passthrough.

## Inputs

| Name | Type | Required | Default | Description |
|---|---|:---:|---|---|
| `name` | `string` | yes | - | Name of the USB hardware mapping in Proxmox VE. |
| `comment` | `string` | no | `null` | Optional description or comment for the mapping. |
| `dev_mappings` | `set(object)` | yes | - | Set of hardware device mapping objects with `id`, `node`, and optional `comment`/`path`. |

### `dev_mappings` object schema

```terraform
set(object({
  id      = string           # USB device ID, e.g. "1234:5678"
  node    = string           # Proxmox node name, e.g. "pve"
  comment = optional(string) # Optional comment for this mapping entry
  path    = optional(string) # Optional USB port path, e.g. "1-1.2"
}))
```

## Outputs

| Name | Type | Description |
|---|---|---|
| `usb_mapped_device` | `object` | Map containing `name` and `id` of the created Proxmox hardware mapping. |

## Example usage

```terraform
module "zigbee_dongle" {
  source = "../../modules/usb_resource_mapping"

  name    = "zigbee-coordinator"
  comment = "Sonoff Zigbee 3.0 USB Dongle Plus"

  dev_mappings = [
    {
      id      = "10c4:ea60"
      node    = "pve"
      comment = "Connected to rear USB 2.0 port"
    }
  ]
}
```

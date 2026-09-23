# Cloud image imports

Reference for cloud images managed through Terraform and uploaded to Proxmox import storage.

## Storage

Terraform downloads importable cloud images to the configured Proxmox import datastore:

```text
import_datastore_id = "local"
```

These images are intended for VM disk imports, not CD-ROM installer attachment.

## Active import

| Key | Filename | Source URL | Purpose |
|---|---|---|---|
| `ubuntu` | `resolute-server-cloudimg-amd64.qcow2` | `https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img` | Ubuntu cloud-init VMs |

The `images` module currently receives only the `ubuntu` entry from
`terraform/live/onprem-pve/main.tf`; therefore `module.images.import_images` exposes only
the Ubuntu image after a normal apply.

## Disabled Debian import configuration

`terraform/live/onprem-pve/variables.tf` retains the following Debian image inputs for a
future deliberate re-enable, but the corresponding `debian` entry in
`module "images"` is commented out and no Debian image is currently imported:

| Key | Filename | Source URL |
|---|---|---|
| `debian` | `debian-13-generic-amd64-20260220-2394.qcow2` | `https://cdimage.debian.org/images/cloud/trixie/20260220-2394/debian-13-generic-amd64-20260220-2394.qcow2` |

## Terraform outputs

After apply, image file IDs are exposed through:

```text
module.images.import_images
```

Expected Ubuntu file ID shape:

```text
local:import/resolute-server-cloudimg-amd64.qcow2
```

Use the file ID as `import_image_file_id` when provisioning a VM from the Ubuntu cloud image.

## Imported image overwrite policy

Terraform sets `overwrite = false` for imported cloud images. This keeps already-imported VM disk images stable when an upstream `current` image URL changes size. To intentionally refresh an image, change the configured filename or remove the old imported image through a deliberate Terraform workflow after reviewing the plan.

## Cloud-init password source

Terraform supports two mutually exclusive mechanisms for providing the shared cloud-init login password:

1. **Local operator file (`cloud_init_password_file`)**: Reads the password from a local file path (defaulting to `/home/operator/.secrets/lab-vm/pass.txt` in operator environments). If the file exists, it is loaded with `pathexpand()`, trimmed with `chomp()`, and marked sensitive. If the file does not exist (such as in CI static validation runners or clean development checkouts), the local expression safely falls back to `null` to prevent missing-file errors and HCL parser panics during TFLint or static evaluations.
2. **Direct variable injection (`cloud_init_password`)**: A nullable, sensitive string variable intended for CI pipeline environments where secrets are injected directly (e.g. via `TF_VAR_cloud_init_password`) without creating disk artifacts.

A Terraform `check "cloud_init_password_source"` block asserts during plan and apply that exactly one source is configured, and verifies that `cloud_init_password_file` exists when specified. The password value is intentionally not stored in `terraform.tfvars.example`, documentation, or Git-tracked files.

Current Terraform module calls that receive this password through the reusable `proxmox_vm` module:

- monolithic Zabbix VM
- managed Zabbix client VMs

The legacy split Zabbix VM block also passes this password, but it is disabled
by default with `zabbix_vms_enabled = false` and depends on a Debian image
import that is not currently enabled. The n8n VM intentionally does not
receive a cloud-init password.

Security notes:

- Keep `/home/operator/.secrets/lab-vm/pass.txt` outside the repository.
- Restrict the file to the local operator account where practical, for example `chmod 600 /home/operator/.secrets/lab-vm/pass.txt`.
- Terraform state may contain provider-rendered cloud-init password attributes. Treat local state files as sensitive and keep them ignored.
- Prefer SSH keys for routine access; use the password mainly for console recovery or bootstrap workflows.

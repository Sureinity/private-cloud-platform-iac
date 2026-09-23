# Bootstrap Terraform Roots

This directory contains standalone, decoupled Terraform configurations for bootstrapping out-of-band infrastructure components.

## Architectural Purpose

Components in `terraform/bootstrap/` are prerequisites for the primary infrastructure environments defined under `terraform/live/`.

### Circular Dependency Prevention

Primary environment state (such as `terraform/live/onprem-pve/`) is intended to be stored in an S3-compatible backend (SeaweedFS). In order to prevent fatal circular dependencies where the state backend manages itself:

1. Bootstrap roots **must not** store their state in the backend they provision.
2. Bootstrap roots use local, off-host backed-up, or dedicated out-of-band state.
3. If the state backend fails, operators can inspect or recover the backend VM independently without needing access to unavailable remote state.

## Layout

```text
terraform/bootstrap/
├── seaweedfs/       # Dedicated standalone root for provisioning the SeaweedFS VM
└── README.md        # Architecture and bootstrap guidance
```

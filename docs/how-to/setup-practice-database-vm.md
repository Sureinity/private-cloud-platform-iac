# Provision and configure practice database VM

Step-by-step procedure to provision the low-resource practice database VM (`db-practice`, VMID `160`) with Terraform and configure either MySQL or PostgreSQL in low-resource mode.

## Prerequisites

- Access to Proxmox VE via management endpoint (`192.0.2.10:8006` or Tailscale).
- Local Terraform environment configured in `terraform/live/onprem-pve/`.
- SSH key `secrets/ssh_keys/priv/home-vm` present locally for guest access.
- Reference baseline: `../reference/database-vm-allocation.md`.

## Step 1: Provision the database VM via Terraform

1. Move to the live Proxmox environment directory:

   ```bash
   cd terraform/live/onprem-pve
   ```

2. Format and validate the configuration:

   ```bash
   terraform fmt -check
   terraform validate
   ```

3. Plan the targeted change to verify that only VM `160` will be created:

   ```bash
   terraform plan -target=module.database_vm
   ```

4. Apply the targeted resource:

   ```bash
   terraform apply -target=module.database_vm
   ```

5. Confirm the VM state on the Proxmox host:

   ```bash
   qm status 160
   ```

## Step 2: Verify connectivity and access

1. Ping the guest over the OPNsense LAN segment:

   ```bash
   ping -c 3 192.0.2.60
   ```

2. Connect via SSH using the `home-vm` key:

   ```bash
   ssh -i secrets/ssh_keys/priv/home-vm ubuntu@192.0.2.60
   ```

3. Inspect initial memory usage:

   ```bash
   free -h
   ```

## Step 3: Install and tune the selected database engine

Select either Option A (MySQL) or Option B (PostgreSQL).

### Option A: MySQL installation and low-resource tuning

1. Update package index and install MySQL server:

   ```bash
   sudo apt update
   sudo apt install -y mysql-server
   ```

2. Create a dedicated configuration snippet `/etc/mysql/mysql.conf.d/99-low-resource.cnf`:

   ```bash
   sudo tee /etc/mysql/mysql.conf.d/99-low-resource.cnf <<'EOF'
   [mysqld]
   # Cap InnoDB buffer pool to 256MB for 1GB RAM envelope
   innodb_buffer_pool_size = 256M
   innodb_log_buffer_size = 16M
   innodb_buffer_pool_instances = 1

   # Connection and table cache limits
   max_connections = 25
   table_open_cache = 400
   table_definition_cache = 400
   thread_cache_size = 8

   # Per-thread memory limits
   sort_buffer_size = 512K
   read_buffer_size = 256K
   read_rnd_buffer_size = 512K
   join_buffer_size = 512K
   EOF
   ```

3. Restart MySQL to apply parameters:

   ```bash
   sudo systemctl restart mysql
   ```

4. Verify service status and memory footprint:

   ```bash
   sudo systemctl status mysql --no-pager
   ps aux | grep [m]ysqld
   free -h
   ```

### Option B: PostgreSQL installation and low-resource tuning

1. Update package index and install PostgreSQL:

   ```bash
   sudo apt update
   sudo apt install -y postgresql postgresql-contrib
   ```

2. Determine installed PostgreSQL version (e.g., 16):

   ```bash
   PG_VER=$(pg_config --version | awk '{print $2}' | cut -d. -f1)
   ```

3. Create the low-resource configuration file `/etc/postgresql/${PG_VER}/main/conf.d/99-low-resource.conf`:

   ```bash
   sudo mkdir -p "/etc/postgresql/${PG_VER}/main/conf.d"
   sudo tee "/etc/postgresql/${PG_VER}/main/conf.d/99-low-resource.conf" <<'EOF'
   # Shared buffers capped to 128MB
   shared_buffers = 128MB
   effective_cache_size = 384MB

   # Per-query / maintenance limits
   work_mem = 4MB
   maintenance_work_mem = 32MB

   # Concurrency
   max_connections = 25

   # Write Ahead Logging
   min_wal_size = 80MB
   max_wal_size = 512MB
   wal_buffers = 4MB
   checkpoint_completion_target = 0.7
   EOF
   ```

4. Restart PostgreSQL to apply parameters:

   ```bash
   sudo systemctl restart postgresql
   ```

5. Verify service status and memory footprint:

   ```bash
   sudo systemctl status postgresql --no-pager
   ps aux | grep [p]ostgres
   free -h
   ```

## Step 4: Verification and practice database creation

### MySQL verification:

```bash
sudo mysql -e "CREATE DATABASE practice_db; SHOW DATABASES;"
```

### PostgreSQL verification:

```bash
sudo -u postgres psql -c "CREATE DATABASE practice_db;"
sudo -u postgres psql -c "\l"
```

## Step 5: Rollback and teardown

To stop the VM when not in practice use:

```bash
qm shutdown 160
```

To destroy the VM and reclaim all `local-lvm` disk space:

```bash
cd terraform/live/onprem-pve
terraform destroy -target=module.database_vm
```

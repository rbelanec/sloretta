# sloretta — Slurm Cluster Ansible

Configures a Slurm cluster on existing OpenStack VMs running Ubuntu 24.04 LTS.
Ansible only configures; instance creation is out of scope.

## Topology

| Node | Role | Reachability |
|------|------|--------------|
| `login01` | slurmctld · slurmdbd · MariaDB · NFS server · munge | Floating IP |
| `gpuNN` | slurmd · NVIDIA driver · NFS client · munge | Private IP only — SSH via ProxyJump through login |

## Prerequisites

### Control machine — pyenv + Ansible

Ansible must run inside a **pyenv-managed virtualenv** on the control machine.
Run the one-time bootstrap script, or follow the steps manually:

```bash
bash scripts/bootstrap_control.sh
```

**Manual steps (what the script does):**

```bash
# 1. Install pyenv if not already present
curl https://pyenv.run | bash
# Add to ~/.zshrc (or ~/.bashrc):
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# 2. Install the target Python version and create a virtualenv
pyenv install 3.12.4          # or whichever 3.11+ version you prefer
pyenv virtualenv 3.12.4 ansible
pyenv local ansible            # writes .python-version — activates automatically

# 3. Install Ansible and required collections
pip install --upgrade pip
pip install ansible>=2.14
ansible-galaxy collection install -r requirements.yml
```

After this, `which ansible` should resolve to somewhere inside
`~/.pyenv/versions/ansible/`. The `.python-version` file in the project root
pins this virtualenv whenever you `cd` into the directory.

### Each cluster VM
- Ubuntu 24.04 LTS
- SSH user `ubuntu` with your public key
- The login node's floating IP must be reachable from the control machine
- Compute nodes must be reachable from the login node on port 22

## OpenStack Security Groups

Create two security groups and apply them as shown.

### `sg-cluster-internal` (applied to login + all compute)

| Protocol | Port(s)       | Source              | Purpose                      |
|----------|---------------|---------------------|------------------------------|
| TCP      | 6817          | sg-cluster-internal | slurmctld                    |
| TCP      | 6818          | sg-cluster-internal | slurmd                       |
| TCP      | 6819          | sg-cluster-internal | slurmdbd                     |
| TCP      | 2049          | sg-cluster-internal | NFS                          |
| TCP+UDP  | 111           | sg-cluster-internal | portmapper (NFS)             |
| TCP      | 60001–63000   | sg-cluster-internal | srun dynamic port range      |
| TCP+UDP  | All           | sg-cluster-internal | intra-cluster (simplest)     |

### `sg-login-external` (applied to login only)

| Protocol | Port | Source    | Purpose          |
|----------|------|-----------|------------------|
| TCP      | 22   | 0.0.0.0/0 | SSH (your IP)    |

> **Note:** Restrict the SSH source to your own IP or VPN range in production.

The `srun` ephemeral port range is configurable in `slurm.conf` via
`SrunPortRange`; the range above matches the Slurm default.  If you change it,
update the security group rule to match.

## Running Ansible from the Login Node (control == login)

The control machine and the login node can be the same host.  This is
convenient when you want to manage the cluster from within the cluster itself.

Two small changes are required — both are pre-commented in the repo:

**`inventory/hosts.yml`** — add a local connection for the login host:
```yaml
login01:
  ansible_host: "203.0.113.10"
  slurm_private_ip: "192.168.1.10"
  ansible_connection: local        # ← uncomment this line
```

**`group_vars/compute.yml`** — drop the ProxyJump (the login node reaches
compute nodes directly on the private network):
```yaml
# Comment out the ProxyJump line:
# ansible_ssh_common_args: "-o ProxyJump=..."

# Uncomment the direct line instead:
ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
```

Then run the bootstrap script and the playbook on the login node itself:
```bash
bash scripts/bootstrap_control.sh
ansible-playbook site.yml --ask-vault-pass
```

Everything else — munge key generation, NFS exports, slurm.conf rendering —
works identically regardless of where Ansible runs.

## Quick Start

```bash
# 1. Clone / enter the project
cd sloretta

# 2. Edit inventory — put in your actual IPs
$EDITOR inventory/hosts.yml

# 3. Create and encrypt the vault secrets file
cp vault/secrets.yml.example vault/secrets.yml
# Edit vault/secrets.yml and set slurm_db_password to something strong
ansible-vault encrypt vault/secrets.yml

# 4. Run the playbook
ansible-playbook site.yml --ask-vault-pass
```

On the first run, the NVIDIA driver install triggers a **reboot** of each
compute node.  The playbook waits for the node to come back before continuing.
Set `nvidia_reboot_after_install: false` in `group_vars/all.yml` to skip this
(useful during testing; re-enable for production).

## Inventory Variables

Each compute host **must** have:

| Variable           | Example         | Description                               |
|--------------------|-----------------|-------------------------------------------|
| `ansible_host`     | `192.168.1.20`  | Private IP (SSH target via ProxyJump)     |
| `slurm_private_ip` | `192.168.1.20`  | Same IP — written to `/etc/hosts`         |
| `slurm_gpu_count`  | `4`             | Number of GPUs on this node               |
| `slurm_gpu_type`   | `a100`          | GPU type string used in Gres= lines       |

Optional per-host overrides (defaults come from Ansible facts):

| Variable             | Default                              |
|----------------------|--------------------------------------|
| `slurm_node_cpus`    | `ansible_processor_vcpus`            |
| `slurm_node_memory`  | `ansible_memtotal_mb × 0.95` (MB)   |

The login host additionally requires `slurm_private_ip` for NFS mount
configuration on compute nodes.

## Cluster-wide Variables (`group_vars/all.yml`)

| Variable                  | Default          | Description                          |
|---------------------------|------------------|--------------------------------------|
| `slurm_cluster_name`      | `mycluster`      | Slurm cluster name                   |
| `slurm_partition_name`    | `gpu`            | Default partition name               |
| `slurm_accounting`        | `true`           | Enable MariaDB + slurmdbd            |
| `nvidia_driver_branch`    | `550`            | e.g. `535`, `545`, `550`             |
| `nvidia_reboot_after_install` | `true`      | Reboot compute after driver install  |
| `nfs_subnet`              | `192.168.1.0/24` | Restrict NFS exports to this CIDR    |
| `cluster_users`           | `[alice, bob]`   | OS users with pinned UIDs            |

## Adding a Node

1. Launch a new VM in OpenStack (Ubuntu 24.04, private network only).
2. Add it to `inventory/hosts.yml` under `compute:` with all required vars.
3. Re-run the playbook:
   ```bash
   ansible-playbook site.yml --ask-vault-pass
   ```
4. The playbook:
   - Gathers fresh facts from the new node
   - Provisions it (common, munge, NFS, NVIDIA, slurm)
   - Re-renders `slurm.conf` on **every** node to include the new `NodeName=` line
   - Fires `scontrol reconfigure` on the controller and restarts `slurmd` on all
     compute nodes via the `slurm config changed` handler

Existing running jobs are not affected by `scontrol reconfigure`.

## Vault Reference

`vault/secrets.yml` (encrypted, gitignored) must contain:

```yaml
slurm_db_password: "<strong password>"
```

Decrypt for editing:
```bash
ansible-vault edit vault/secrets.yml
```

Use a password file for non-interactive runs:
```bash
echo "my-vault-pass" > .vault_pass && chmod 600 .vault_pass
ansible-playbook site.yml --vault-password-file .vault_pass
```

## Munge Key

The munge key is generated **once** on the login node (`mungekey --create`,
idempotent via `creates:`), fetched to `.munge/munge.key` on the control
machine (gitignored), then pushed to every node with `munge:munge 0400`
ownership.  The key is never regenerated as long as the file exists on the
login node.

To rotate: delete `/etc/munge/munge.key` on the login node, delete
`.munge/munge.key` locally, then re-run the playbook.

## Accounting

When `slurm_accounting: true` (default):

- MariaDB is installed on the login node
- The DB and user are created idempotently
- `slurmdbd` is configured and started
- The cluster is registered with `sacctmgr` on first run

To disable accounting entirely, set `slurm_accounting: false` in
`group_vars/all.yml`.  This sets `AccountingStorageType=accounting_storage/none`
in `slurm.conf` and skips MariaDB/slurmdbd setup.

## GPU Scheduling

`slurm.conf` uses `SelectType=select/cons_tres` with `GresTypes=gpu`.
`cgroup.conf` sets `ConstrainDevices=yes`, which fences jobs to their
allocated `/dev/nvidiaN` devices via the kernel cgroup devices controller.
`gres.conf` maps devices explicitly instead of using NVML autodetect, because
Ubuntu's `slurm-wlm` package is not built against `libnvidia-ml`.

Example job:
```bash
srun --gres=gpu:2 --pty bash    # allocate 2 GPUs
nvidia-smi                       # verify CUDA_VISIBLE_DEVICES fencing
```

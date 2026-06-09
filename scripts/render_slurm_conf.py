"""
Render roles/slurm_common/templates/slurm.conf.j2 against a sample 2-node
inventory so the NodeName lines can be sanity-checked without running Ansible.

Usage:
    python scripts/render_slurm_conf.py
"""

import pathlib
from jinja2 import Environment, FileSystemLoader, StrictUndefined

TEMPLATE_DIR = pathlib.Path(__file__).parent.parent / "roles/slurm_common/templates"

# ── Simulated inventory & hostvars ──────────────────────────────────────────
# These mirror what Ansible would supply after fact-gathering against the
# sample inventory/hosts.yml (64-vCPU / 512 GiB RAM nodes).

groups = {
    "login":   ["login01"],
    "compute": ["gpu01", "gpu02"],
    "all":     ["login01", "gpu01", "gpu02"],
}

hostvars = {
    "login01": {
        "ansible_host":      "203.0.113.10",
        "slurm_private_ip":  "192.168.1.10",
        "ansible_processor_vcpus": 8,
        "ansible_memtotal_mb":     16000,
    },
    "gpu01": {
        "ansible_host":            "192.168.1.20",
        "slurm_private_ip":        "192.168.1.20",
        "slurm_gpu_count":         4,
        "slurm_gpu_type":          "a100",
        # Facts from the node (64 vCPUs, 512 GiB RAM)
        "ansible_processor_vcpus": 64,
        "ansible_memtotal_mb":     524288,
        # Uncomment to test manual overrides:
        # "slurm_node_cpus":   64,
        # "slurm_node_memory": 450000,
    },
    "gpu02": {
        "ansible_host":            "192.168.1.21",
        "slurm_private_ip":        "192.168.1.21",
        "slurm_gpu_count":         4,
        "slurm_gpu_type":          "a100",
        "ansible_processor_vcpus": 64,
        "ansible_memtotal_mb":     524288,
    },
}

# ── Global variables (group_vars/all.yml) ───────────────────────────────────
context = {
    "groups":               groups,
    "hostvars":             hostvars,
    "slurm_cluster_name":   "mycluster",
    "slurm_partition_name": "gpu",
    "slurm_accounting":     True,
    "slurm_cgroup_plugin":  "cgroup/v2",
}

env = Environment(
    loader=FileSystemLoader(str(TEMPLATE_DIR)),
    undefined=StrictUndefined,
    trim_blocks=True,
    lstrip_blocks=True,
)

for tpl_name in ("slurm.conf.j2", "cgroup.conf.j2", "gres.conf.j2"):
    tpl = env.get_template(tpl_name)
    rendered = tpl.render(**context)
    print(f"\n{'='*70}")
    print(f"  {tpl_name}")
    print(f"{'='*70}")
    print(rendered)

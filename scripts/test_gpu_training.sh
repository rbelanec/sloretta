#!/bin/bash
#SBATCH --job-name=gpu-training-test
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gres=gpu:h200:1
#SBATCH --time=00:10:00
#SBATCH --output=/home/%u/gpu-training-test-%j.out
#SBATCH --error=/home/%u/gpu-training-test-%j.err

set -euo pipefail

export PYENV_ROOT="/home/$(whoami)/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
pyenv activate ml

echo "=== GPU Training Smoke Test ==="
echo "Node:    $(hostname)"
echo "Date:    $(date)"
echo "CUDA:    $(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader)"
echo ""

python3 - <<'EOF'
import time
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM
from torch.optim import AdamW

assert torch.cuda.is_available(), "CUDA not available — check NVIDIA driver and gres config"
device = torch.device("cuda")
print(f"Device:  {torch.cuda.get_device_name(0)}")
print(f"VRAM:    {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")
print()

model_name = "distilgpt2"
print(f"Loading {model_name} ...")
tokenizer = AutoTokenizer.from_pretrained(model_name)
tokenizer.pad_token = tokenizer.eos_token
model = AutoModelForCausalLM.from_pretrained(model_name).to(device)

sentences = [
    "The GPU cluster is running Slurm and everything works.",
    "Training large language models requires significant compute.",
    "NVIDIA H200 GPUs provide excellent memory bandwidth.",
    "Distributed training across multiple nodes improves throughput.",
]
inputs = tokenizer(sentences, return_tensors="pt", padding=True, truncation=True, max_length=32).to(device)
labels = inputs["input_ids"].clone()

optimizer = AdamW(model.parameters(), lr=5e-5)
model.train()

print("Running 20 training steps ...")
t0 = time.time()
for step in range(20):
    optimizer.zero_grad()
    outputs = model(**inputs, labels=labels)
    outputs.loss.backward()
    optimizer.step()
    if (step + 1) % 5 == 0:
        mem = torch.cuda.memory_allocated() / 1e9
        print(f"  step {step+1:2d}/20  loss={outputs.loss.item():.4f}  gpu_mem={mem:.2f} GB")

elapsed = time.time() - t0
print()
print(f"Done in {elapsed:.1f}s — GPU training is working correctly.")
EOF

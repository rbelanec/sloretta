#!/usr/bin/env bash
# Bootstrap the Ansible control environment on a fresh machine.
# Installs pyenv, creates an "ansible" virtualenv, installs Ansible + collections.
# Safe to re-run — all steps are idempotent.

set -euo pipefail

PYTHON_VERSION="3.12.4"
VENV_NAME="ansible"
PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"

# ── 1. Install pyenv if missing ─────────────────────────────────────────────
if ! command -v pyenv &>/dev/null; then
    echo "==> Installing pyenv..."
    curl -fsSL https://pyenv.run | bash

    # Detect shell rc file
    if [[ "$SHELL" == */zsh ]]; then
        RC="$HOME/.zshrc"
    else
        RC="$HOME/.bashrc"
    fi

    cat >>"$RC" <<'EOF'

# pyenv (added by sloretta/bootstrap_control.sh)
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOF
    echo "==> pyenv installed. Sourcing init for this session..."
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
else
    echo "==> pyenv already installed ($(pyenv --version))"
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)" || true
    eval "$(pyenv virtualenv-init -)" || true
fi

# ── 2. Install Python version ────────────────────────────────────────────────
if ! pyenv versions --bare | grep -qx "$PYTHON_VERSION"; then
    echo "==> Installing Python $PYTHON_VERSION via pyenv..."
    pyenv install "$PYTHON_VERSION"
else
    echo "==> Python $PYTHON_VERSION already installed"
fi

# ── 3. Create virtualenv ─────────────────────────────────────────────────────
if ! pyenv versions --bare | grep -qx "$VENV_NAME"; then
    echo "==> Creating pyenv virtualenv '$VENV_NAME'..."
    pyenv virtualenv "$PYTHON_VERSION" "$VENV_NAME"
else
    echo "==> Virtualenv '$VENV_NAME' already exists"
fi

# ── 4. Pin the virtualenv to this project directory ──────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
echo "$VENV_NAME" >"$PROJECT_ROOT/.python-version"
echo "==> Pinned virtualenv '$VENV_NAME' in $PROJECT_ROOT/.python-version"

# ── 5. Install Ansible and collections ───────────────────────────────────────
PYENV_VERSION="$VENV_NAME" pip install --upgrade pip --quiet
PYENV_VERSION="$VENV_NAME" pip install "ansible>=2.14" --quiet
echo "==> Ansible $(PYENV_VERSION=$VENV_NAME ansible --version | head -1) installed"

PYENV_VERSION="$VENV_NAME" ansible-galaxy collection install -r "$PROJECT_ROOT/requirements.yml"
echo "==> Ansible collections installed"

echo ""
echo "Done. cd into the project directory to activate the virtualenv automatically,"
echo "or run: pyenv activate $VENV_NAME"

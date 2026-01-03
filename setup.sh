#!/bin/bash
#
# setup.sh - Initializes the Ansible Secrets administrative environment
# and runtime helper components.
#
# This script creates the administrative toolkit in /opt/ansible_secrets
# and installs the runtime helpers to /usr/local/bin and /usr/local/lib.
# It prioritizes files from the current repository as the source of truth.

set -euo pipefail

# --- Configuration ---
# Administrative Paths
BASE_DIR="/opt/ansible_secrets"
FILES_DIR="${BASE_DIR}/files"
TASKS_DIR="${BASE_DIR}/tasks"
VARS_DIR="${BASE_DIR}/group_vars/all"
VAULT_FILE="${VARS_DIR}/vault.yml"
VAULT_PASS_FILE="${BASE_DIR}/.ansible_vault_password"
ANSIBLE_CFG="${BASE_DIR}/ansible.cfg"
INVENTORY="${BASE_DIR}/inventory"
ADD_SECRET_SCRIPT="${BASE_DIR}/add-secret.sh"
PLAYBOOK_FILE="${BASE_DIR}/deploy_secrets.yml"
VENV_PATH="${BASE_DIR}/venv/bin/activate"
VENV_DIR="${BASE_DIR}/venv"
VENV_PYTHON="${VENV_DIR}/bin/python"
VENV_PIP="${VENV_DIR}/bin/pip"

# Runtime Paths
RUNTIME_BIN="/usr/local/bin"
RUNTIME_LIB="/usr/local/lib/ansible_secret_helpers"
GET_SECRET_BASH="${RUNTIME_BIN}/get_secret.sh"
SECURE_APP_BASH="${RUNTIME_BIN}/secure-app.sh"

# Local Repository Source Paths
REPO_LIB_SRC="./ansible_secret_helpers"
REPO_GET_SECRET_SRC="./get_secret.sh"
REPO_SECURE_APP_SRC="./secure-app.sh"
REPO_ADD_SECRET_SRC="./add-secret.sh"
REPO_INVENTORY_SRC="./inventory"
REPO_ANSIBLE_CFG_SRC="./ansible.cfg"
REPO_PLAYBOOK_SRC="./deploy_secrets.yml"
REPO_TASKS_SRC="./tasks"

# Security Identities
SERVICE_USER="service_account"
SECRET_GROUP="appsecretaccess"
CURRENT_USER="${SUDO_USER:-$(whoami)}"

echo "--> Initializing Ansible Secrets Administrative Project at ${BASE_DIR}..."

# Ensure service account and group exist for consistent ownership
echo "--> Ensuring service account '${SERVICE_USER}' and group '${SECRET_GROUP}' exist..."
if ! getent group "$SECRET_GROUP" > /dev/null; then
    sudo groupadd --system "$SECRET_GROUP"
fi

if ! id -u "$SERVICE_USER" > /dev/null 2>&1; then
    sudo useradd --system --gid "$SECRET_GROUP" --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
else
    if ! id -nG "$SERVICE_USER" | tr ' ' '\n' | grep -qx "$SECRET_GROUP"; then
        sudo usermod -a -G "$SECRET_GROUP" "$SERVICE_USER"
    fi
fi

# Ensure the invoking user is part of the access group for administrative tasks
if id -u "$CURRENT_USER" > /dev/null 2>&1; then
    if [[ "$CURRENT_USER" != "$SERVICE_USER" ]]; then
        if ! id -nG "$CURRENT_USER" | tr ' ' '\n' | grep -qx "$SECRET_GROUP"; then
            sudo usermod -a -G "$SECRET_GROUP" "$CURRENT_USER"
        fi
    fi
fi

# 1. Create administrative directory structure
sudo mkdir -p "$FILES_DIR" "$TASKS_DIR" "$VARS_DIR"
sudo mkdir -p "$RUNTIME_BIN"

# 1b. Ensure Python virtual environment exists for Ansible tooling
if [[ ! -f "$VENV_PATH" ]]; then
    echo "--> Creating Python virtual environment at ${VENV_DIR}..."
    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required to create the virtual environment." >&2
        exit 1
    fi
    sudo -u "$CURRENT_USER" python3 -m venv "$VENV_DIR"
fi

# Install required Python packages if missing
if [[ -x "$VENV_PYTHON" ]]; then
    if ! sudo -u "$CURRENT_USER" "$VENV_PYTHON" -m pip show ansible-core >/dev/null 2>&1 || ! sudo -u "$CURRENT_USER" "$VENV_PYTHON" -m pip show gnupg >/dev/null 2>&1; then
        echo "--> Installing Python dependencies (ansible-core, gnupg) into venv..."
        sudo -u "$CURRENT_USER" "$VENV_PYTHON" -m pip install --upgrade pip
        sudo -u "$CURRENT_USER" "$VENV_PYTHON" -m pip install ansible-core gnupg
    fi
fi

# 2. Create the Ansible Vault password file
if [[ ! -f "$VAULT_PASS_FILE" ]]; then
    echo "--> Creating vault password file..."
    openssl rand -base64 24 | sudo tee "$VAULT_PASS_FILE" > /dev/null
    sudo chmod 600 "$VAULT_PASS_FILE"
else
    echo "--> Vault password file already exists. Skipping."
fi

# 3. Deploy ansible.cfg
if [[ -f "$REPO_ANSIBLE_CFG_SRC" ]]; then
    echo "--> Copying ansible.cfg from repository..."
    sudo cp "$REPO_ANSIBLE_CFG_SRC" "$ANSIBLE_CFG"
else
    echo "--> Creating default ansible.cfg..."
    sudo tee "$ANSIBLE_CFG" > /dev/null <<EOF
[defaults]
inventory = ./inventory
vault_password_file = ./.ansible_vault_password
host_key_checking = False

[privilege_escalation]
become = true
become_method = sudo
become_user = root
become_ask_pass = true
EOF
fi
sudo chmod 0640 "$ANSIBLE_CFG"

# 4. Deploy inventory
if [[ -f "$REPO_INVENTORY_SRC" ]]; then
    echo "--> Copying inventory from repository..."
    sudo cp "$REPO_INVENTORY_SRC" "$INVENTORY"
else
    echo "--> Creating useful local inventory..."
    sudo tee "$INVENTORY" > /dev/null <<EOF
[local_server]
localhost ansible_connection=local ansible_python_interpreter="{{ ansible_playbook_python }}"
EOF
fi
sudo chmod 0640 "$INVENTORY"

# 5. Deploy Playbook and Tasks
if [[ -f "$REPO_PLAYBOOK_SRC" ]]; then
    echo "--> Copying playbook from repository..."
    sudo cp "$REPO_PLAYBOOK_SRC" "$PLAYBOOK_FILE"
fi

if [[ -d "$REPO_TASKS_SRC" ]]; then
    echo "--> Copying tasks from repository..."
    sudo rsync -a --delete "$REPO_TASKS_SRC/" "$TASKS_DIR/"
fi

# 6. Create/Deploy add-secret.sh
if [[ -f "$REPO_ADD_SECRET_SRC" ]]; then
    echo "--> Copying add-secret.sh from repository..."
    sudo install -m 0750 "$REPO_ADD_SECRET_SRC" "$ADD_SECRET_SCRIPT"
else
    echo "--> Creating add-secret.sh..."
    sudo tee "$ADD_SECRET_SCRIPT" > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
BASE_DIR="/opt/ansible_secrets"
FILES_DIR="${BASE_DIR}/files"
VAULT_FILE="${BASE_DIR}/group_vars/all/vault.yml"
VENV_PATH="${BASE_DIR}/venv/bin/activate"
if [[ $# -ne 1 ]]; then echo "Usage: $0 <secret_name>" >&2; exit 1; fi
SECRET_NAME="$1"
OUTPUT_FILE="${FILES_DIR}/${SECRET_NAME}_secret.txt.gpg"
read -sp "Enter password for '${SECRET_NAME}': " SECRET_PASSWORD
echo
if [[ -f "$VENV_PATH" ]]; then source "$VENV_PATH"; fi
GPG_PASSPHRASE=$(ansible-vault view "$VAULT_FILE" | grep 'app_gpg_passphrase:' | awk '{printf "%s", $2}' | tr -d \''"')
if [[ -z "$GPG_PASSPHRASE" ]]; then echo "Error: GPG passphrase not found." >&2; exit 1; fi
printf '%s' "$SECRET_PASSWORD" | gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase "$GPG_PASSPHRASE" --output "$OUTPUT_FILE"
echo "✅ Encrypted secret saved to: ${OUTPUT_FILE}"
EOF
fi
sudo chmod 0750 "$ADD_SECRET_SCRIPT"

# 7. Initialize Runtime Helpers (System-wide)
echo "--> Initializing Runtime Helpers in /usr/local..."
sudo mkdir -p "$RUNTIME_LIB"

if [[ -f "$REPO_GET_SECRET_SRC" ]]; then
    echo "--> Copying get_secret.sh from repository..."
    sudo install -m 0750 "$REPO_GET_SECRET_SRC" "$GET_SECRET_BASH"
else
    echo "--> Creating get_secret.sh fallback..."
    sudo tee "$GET_SECRET_BASH" > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
CREDENTIAL_STORE="/opt/credential_store"
PASSPHRASE_FILE="${CREDENTIAL_STORE}/.gpg_passphrase"
if [[ $# -ne 1 ]]; then echo "Usage: get_secret <secret_name>" >&2; exit 1; fi
SECRET_FILE="${CREDENTIAL_STORE}/${1}_secret.txt.gpg"
gpg --batch --quiet --yes --passphrase-file "$PASSPHRASE_FILE" --decrypt "$SECRET_FILE"
EOF
    sudo chmod 0750 "$GET_SECRET_BASH"
fi

if [[ -f "$REPO_SECURE_APP_SRC" ]]; then
    echo "--> Copying secure-app.sh from repository..."
    sudo install -m 0755 "$REPO_SECURE_APP_SRC" "$SECURE_APP_BASH"
fi

if [[ -d "$REPO_LIB_SRC" ]]; then
    echo "--> Copying Python helpers from repository directory..."
    sudo rsync -a --delete "$REPO_LIB_SRC/" "$RUNTIME_LIB/"
else
    echo "--> Error: Python helper source directory '${REPO_LIB_SRC}' not found." >&2
    exit 1
fi

# Set Runtime Permissions
sudo chown -R "${SERVICE_USER}:${SECRET_GROUP}" "$RUNTIME_LIB"
sudo chmod 0750 "$RUNTIME_LIB"
if compgen -G "${RUNTIME_LIB}/*" > /dev/null; then
    sudo chmod 0640 "${RUNTIME_LIB}/"*
fi
sudo chown "${SERVICE_USER}:${SECRET_GROUP}" "$GET_SECRET_BASH"

# 8. Finalize Administrative Ownership
sudo chown -R "$(whoami):$(id -gn)" "$BASE_DIR"

echo "✅ Initialization complete."
echo "--------------------------------------------------------"
echo "Administrative Project: ${BASE_DIR}"
echo "Bash Helper:            ${GET_SECRET_BASH}"
echo "Python Helpers:         ${RUNTIME_LIB}/"
echo "--------------------------------------------------------"

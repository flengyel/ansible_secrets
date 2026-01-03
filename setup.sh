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

# Runtime Paths
RUNTIME_BIN="/usr/local/bin"
RUNTIME_LIB="/usr/local/lib/ansible_secret_helpers"
GET_SECRET_BASH="${RUNTIME_BIN}/get_secret.sh"

# Local Repository Source Paths
REPO_LIB_SRC="./ansible_secret_helpers"
REPO_GET_SECRET_SRC="./get_secret.sh"
REPO_ADD_SECRET_SRC="./add-secret.sh"
REPO_INVENTORY_SRC="./inventory"
REPO_ANSIBLE_CFG_SRC="./ansible.cfg"
REPO_PLAYBOOK_SRC="./deploy_secrets.yml"
REPO_TASKS_SRC="./tasks"

# Security Identities
SERVICE_USER="service_account"
SECRET_GROUP="appsecretaccess"

echo "--> Initializing Ansible Secrets Administrative Project at ${BASE_DIR}..."

# 0. Create the dedicated service user
sudo useradd --system --shell /sbin/nologin --comment "Service account for Bash and Python apps" "$SERVICE_USER"

# Create the dedicated access group
sudo groupadd --system "$SECRET_GROUP"

# Add the service user to the access group
sudo usermod -aG "$SECRET_GROUP" "$SERVICE_USER" 

# Add yourself and any other required users to the access group
sudo usermod -aG appsecretaccess "$USER"


# 1. Create administrative directory structure
sudo mkdir -p "$FILES_DIR" "$TASKS_DIR" "$VARS_DIR"

# 2. Create the Ansible Vault password file
if [[ ! -f "$VAULT_PASS_FILE" ]]; then
    echo "--> Creating vault password file..."
    openssl rand -base64 48 | sudo tee "$VAULT_PASS_FILE" > /dev/null
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
    sudo cp -r "$REPO_TASKS_SRC/"* "$TASKS_DIR/"
fi

# 6. Create/Deploy add-secret.sh
if [[ -f "$REPO_ADD_SECRET_SRC" ]]; then
    echo "--> Copying add-secret.sh from repository..."
    sudo cp "$REPO_ADD_SECRET_SRC" "$ADD_SECRET_SCRIPT"
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
OUTPUT_FILE="${FILES_DIR}/${SECRET_NAME}_pswd.txt.gpg"
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
    sudo cp "$REPO_GET_SECRET_SRC" "$GET_SECRET_BASH"
else
    echo "--> Creating get_secret.sh fallback..."
    sudo tee "$GET_SECRET_BASH" > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
CREDENTIAL_STORE="/opt/credential_store"
PASSPHRASE_FILE="${CREDENTIAL_STORE}/.gpg_passphrase"
if [[ $# -ne 1 ]]; then echo "Usage: get_secret <secret_name>" >&2; exit 1; fi
SECRET_FILE="${CREDENTIAL_STORE}/${1}_pswd.txt.gpg"
GPG_PASSPHRASE=$(cat "$PASSPHRASE_FILE")
gpg --batch --quiet --decrypt --passphrase "$GPG_PASSPHRASE" "$SECRET_FILE"
EOF
fi

if [[ -d "$REPO_LIB_SRC" ]]; then
    echo "--> Copying Python helpers from repository directory..."
    sudo cp "$REPO_LIB_SRC"/*.py "$RUNTIME_LIB/"
else
    echo "--> Error: Python helper source directory '${REPO_LIB_SRC}' not found." >&2
    exit 1
fi

# Set Runtime Permissions
sudo chown -R "${SERVICE_USER}:${SECRET_GROUP}" "$RUNTIME_LIB"
sudo chmod 0750 "$RUNTIME_LIB"
sudo chmod 0640 "${RUNTIME_LIB}/"*
sudo chown "${SERVICE_USER}:${SECRET_GROUP}" "$GET_SECRET_BASH"
sudo chmod 0750 "$GET_SECRET_BASH"

# 8. Finalize Administrative Ownership
sudo chown -R "$(whoami):$(id -gn)" "$BASE_DIR"

echo "✅ Initialization complete."
echo "--------------------------------------------------------"
echo "Administrative Project: ${BASE_DIR}"
echo "Bash Helper:            ${GET_SECRET_BASH}"
echo "Python Helpers:         ${RUNTIME_LIB}/"
echo "--------------------------------------------------------"


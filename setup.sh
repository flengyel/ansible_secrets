#!/bin/bash
#
# setup.sh - Initializes the Ansible Secrets administrative environment
# and runtime helper components.
#
# This script creates the administrative toolkit in /opt/ansible_secrets
# and installs the runtime helpers to /usr/local/bin and /usr/local/lib.
# It prioritizes files from the current repository as the source of truth.
#
# Requirements:
#   - Run from the repository root (./setup.sh)
#   - You will be prompted ONLY for your sudo password (if needed).
#   - The Ansible Vault password and the GPG passphrase are generated automatically (48 chars).

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
VENV_ANSIBLE_VAULT="${VENV_DIR}/bin/ansible-vault"

# Runtime Paths
RUNTIME_BIN="/usr/local/bin"
RUNTIME_LIB="/usr/local/lib/ansible_secret_helpers"
GET_SECRET_BASH="${RUNTIME_BIN}/get_secret.sh"
SECURE_APP_BASH="${RUNTIME_BIN}/secure-app.sh"

# Local Repository Source Paths (script must be run from repo root)
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

# The "admin" is the invoking human user (not root). If run via sudo, use $SUDO_USER.
ADMIN_USER="${SUDO_USER:-$(whoami)}"
ADMIN_GROUP="$(id -gn "$ADMIN_USER" 2>/dev/null || true)"

# --- Helpers ---
die() { echo "Error: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# Run a command as the admin user (useful if script is invoked with sudo)
run_as_admin() {
  if [[ "$(id -u)" -eq 0 ]]; then
    sudo -u "$ADMIN_USER" "$@"
  else
    "$@"
  fi
}

# --- Sanity checks ---
need_cmd sudo
need_cmd openssl
need_cmd python3
need_cmd rsync

# Refuse to run as root directly (without sudo context), to avoid wrong ownership.
if [[ "$(id -u)" -eq 0 && -z "${SUDO_USER:-}" ]]; then
  die "Do not run this script as root directly. Run as a normal user with sudo access: ./setup.sh"
fi
[[ -n "$ADMIN_GROUP" ]] || die "Unable to determine admin group for user '$ADMIN_USER'"

echo "--> Initializing Ansible Secrets Administrative Project at ${BASE_DIR}..."
echo "--> Admin user: ${ADMIN_USER} (group: ${ADMIN_GROUP})"

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

# Ensure the admin user is part of the access group (may require re-login to take effect)
if id -u "$ADMIN_USER" > /dev/null 2>&1; then
  if [[ "$ADMIN_USER" != "$SERVICE_USER" ]]; then
    if ! id -nG "$ADMIN_USER" | tr ' ' '\n' | grep -qx "$SECRET_GROUP"; then
      sudo usermod -a -G "$SECRET_GROUP" "$ADMIN_USER" || true
      echo "--> NOTE: '${ADMIN_USER}' was added to '${SECRET_GROUP}'. Log out/in if group changes do not apply immediately."
    fi
  fi
fi

# 1. Create administrative directory structure with correct ownership (fixes venv permission errors)
echo "--> Creating administrative directory structure..."
sudo mkdir -p "$FILES_DIR" "$TASKS_DIR" "$VARS_DIR"
sudo chown -R "$ADMIN_USER:$ADMIN_GROUP" "$BASE_DIR"
sudo chmod 0750 "$BASE_DIR" "$FILES_DIR" "$TASKS_DIR"
sudo chmod 0750 "$(dirname "$VARS_DIR")" "$VARS_DIR"

# Ensure runtime base paths exist
sudo mkdir -p "$RUNTIME_BIN"
sudo mkdir -p "$RUNTIME_LIB"

# 1b. Ensure Python virtual environment exists for Ansible tooling
if [[ ! -x "$VENV_PYTHON" ]]; then
  echo "--> Creating Python virtual environment at ${VENV_DIR}..."
  run_as_admin python3 -m venv "$VENV_DIR"
fi

# Install required Python packages if missing
if [[ -x "$VENV_PYTHON" ]]; then
  if ! run_as_admin "$VENV_PYTHON" -m pip show ansible-core >/dev/null 2>&1 \
     || ! run_as_admin "$VENV_PYTHON" -m pip show gnupg >/dev/null 2>&1; then
    echo "--> Installing Python dependencies (ansible-core, gnupg) into venv..."
    run_as_admin "$VENV_PYTHON" -m pip install --upgrade pip
    run_as_admin "$VENV_PYTHON" -m pip install ansible-core gnupg
  fi
else
  die "Virtualenv python not found/executable at: $VENV_PYTHON"
fi

# 2. Create the Ansible Vault password file (48 characters), non-interactive
if [[ ! -f "$VAULT_PASS_FILE" ]]; then
  echo "--> Creating vault password file (48 chars) at ${VAULT_PASS_FILE}..."
  VAULT_PASSWORD="$(openssl rand -base64 36 | tr -d '\n')"
  tmp_pw="$(mktemp)"
  chmod 600 "$tmp_pw"
  printf '%s\n' "$VAULT_PASSWORD" > "$tmp_pw"
  sudo install -m 0600 -o "$ADMIN_USER" -g "$ADMIN_GROUP" "$tmp_pw" "$VAULT_PASS_FILE"
  rm -f "$tmp_pw"
else
  echo "--> Vault password file already exists. Skipping."
  sudo chown "$ADMIN_USER:$ADMIN_GROUP" "$VAULT_PASS_FILE" || true
  sudo chmod 0600 "$VAULT_PASS_FILE" || true
fi

# 2b. Create the encrypted vault.yml containing the single GPG passphrase (48 chars), non-interactive
if [[ ! -f "$VAULT_FILE" ]]; then
  echo "--> Creating encrypted vault file at ${VAULT_FILE} (48-char GPG passphrase)..."
  [[ -x "$VENV_ANSIBLE_VAULT" ]] || die "ansible-vault not found in venv at: $VENV_ANSIBLE_VAULT"

  GPG_PASSPHRASE="$(openssl rand -base64 48 | tr -d '\n')"

  # Tighten permissions during file creation (file content is encrypted, but do it anyway).
  old_umask="$(umask)"
  umask 077

  # IMPORTANT:
  #   - do not allow ansible-vault to pick up ansible.cfg from the repo root (it will try to read ./.ansible_vault_password from the repo)
  #   - do not use /dev/stdin (ansible-vault can resolve stdin to a transient /proc/*/fd/pipe:* path)
  #
  # Use a FIFO so plaintext YAML never touches disk, while still giving ansible-vault a stable filesystem path.
  tmp_dir="$(run_as_admin mktemp -d /tmp/ansible-secrets-vault.XXXXXX)"
  fifo="${tmp_dir}/vault_plain.yml"
  empty_cfg="${tmp_dir}/ansible.cfg"

  run_as_admin mkfifo -m 600 "$fifo"
  run_as_admin sh -c ": > '$empty_cfg'"
  run_as_admin chmod 600 "$empty_cfg"

  writer_pid=""

  cleanup_vault_tmp() {
    # If the writer is blocked on the FIFO and we exit early, kill it.
    if [[ -n "${writer_pid:-}" ]]; then
      kill "$writer_pid" 2>/dev/null || true
      wait "$writer_pid" 2>/dev/null || true
    fi
    run_as_admin rm -rf "$tmp_dir" 2>/dev/null || true
  }

  # Ensure we don't leave a blocked background writer on failure.
  trap cleanup_vault_tmp EXIT

  # Writer: sends plaintext YAML into FIFO (plaintext exists only in RAM/pipe buffers).
  ( printf 'app_gpg_passphrase: "%s"\n' "$GPG_PASSPHRASE" > "$fifo" ) &
  writer_pid=$!

  # Reader: encrypt FIFO -> vault.yml, forcing ansible to ignore repo-local config.
  run_as_admin env ANSIBLE_CONFIG="$empty_cfg" \
    "$VENV_ANSIBLE_VAULT" encrypt \
      --vault-password-file "$VAULT_PASS_FILE" \
      --output "$VAULT_FILE" \
      "$fifo"

  wait "$writer_pid"
  writer_pid=""

  cleanup_vault_tmp
  trap - EXIT

  umask "$old_umask"

  sudo chown "$ADMIN_USER:$ADMIN_GROUP" "$VAULT_FILE"
  sudo chmod 0640 "$VAULT_FILE"

  unset GPG_PASSPHRASE
else
  echo "--> Vault file already exists. Skipping."
  sudo chown "$ADMIN_USER:$ADMIN_GROUP" "$VAULT_FILE" || true
  sudo chmod 0640 "$VAULT_FILE" || true
fi

# 3. Deploy ansible.cfg
if [[ -f "$REPO_ANSIBLE_CFG_SRC" ]]; then
  echo "--> Copying ansible.cfg from repository..."
  sudo install -m 0640 -o "$ADMIN_USER" -g "$ADMIN_GROUP" "$REPO_ANSIBLE_CFG_SRC" "$ANSIBLE_CFG"
else
  echo "--> Creating default ansible.cfg..."
  tmp_cfg="$(mktemp)"
  chmod 600 "$tmp_cfg"
  cat > "$tmp_cfg" <<EOF
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
  sudo install -m 0640 -o "$ADMIN_USER" -g "$ADMIN_GROUP" "$tmp_cfg" "$ANSIBLE_CFG"
  rm -f "$tmp_cfg"
fi

# 4. Deploy inventory
if [[ -f "$REPO_INVENTORY_SRC" ]]; then
  echo "--> Copying inventory from repository..."
  sudo install -m 0640 -o "$ADMIN_USER" -g "$ADMIN_GROUP" "$REPO_INVENTORY_SRC" "$INVENTORY"
else
  echo "--> Creating useful local inventory..."
  tmp_inv="$(mktemp)"
  chmod 600 "$tmp_inv"
  cat > "$tmp_inv" <<EOF
[local_server]
localhost ansible_connection=local ansible_python_interpreter="{{ ansible_playbook_python }}"
EOF
  sudo install -m 0640 -o "$ADMIN_USER" -g "$ADMIN_GROUP" "$tmp_inv" "$INVENTORY"
  rm -f "$tmp_inv"
fi

# 5. Deploy Playbook and Tasks
if [[ -f "$REPO_PLAYBOOK_SRC" ]]; then
  echo "--> Copying playbook from repository..."
  sudo install -m 0640 -o "$ADMIN_USER" -g "$ADMIN_GROUP" "$REPO_PLAYBOOK_SRC" "$PLAYBOOK_FILE"
fi

if [[ -d "$REPO_TASKS_SRC" ]]; then
  echo "--> Copying tasks from repository..."
  sudo rsync -a --delete "$REPO_TASKS_SRC/" "$TASKS_DIR/"
  sudo chown -R "$ADMIN_USER:$ADMIN_GROUP" "$TASKS_DIR"
  sudo find "$TASKS_DIR" -type d -exec chmod 0750 {} +
  sudo find "$TASKS_DIR" -type f -exec chmod 0640 {} +
fi

# 6. Create/Deploy add-secret.sh (admin utility)
if [[ -f "$REPO_ADD_SECRET_SRC" ]]; then
  echo "--> Copying add-secret.sh from repository..."
  sudo install -m 0750 -o "$ADMIN_USER" -g "$ADMIN_GROUP" "$REPO_ADD_SECRET_SRC" "$ADD_SECRET_SCRIPT"
else
  echo "--> Creating add-secret.sh fallback..."
  tmp_add="$(mktemp)"
  chmod 600 "$tmp_add"
  cat > "$tmp_add" <<'EOF'
#!/bin/bash
set -euo pipefail

BASE_DIR="/opt/ansible_secrets"
FILES_DIR="${BASE_DIR}/files"
VAULT_FILE="${BASE_DIR}/group_vars/all/vault.yml"
VAULT_PASS_FILE="${BASE_DIR}/.ansible_vault_password"
VENV_ANSIBLE_VAULT="${BASE_DIR}/venv/bin/ansible-vault"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <secret_name>" >&2
  exit 1
fi

SECRET_NAME="$1"
OUTPUT_FILE="${FILES_DIR}/${SECRET_NAME}_secret.txt.gpg"

[[ -d "$FILES_DIR" ]] || { echo "Error: missing $FILES_DIR" >&2; exit 1; }
[[ -f "$VAULT_FILE" ]] || { echo "Error: missing $VAULT_FILE" >&2; exit 1; }
[[ -f "$VAULT_PASS_FILE" ]] || { echo "Error: missing $VAULT_PASS_FILE" >&2; exit 1; }
[[ -x "$VENV_ANSIBLE_VAULT" ]] || { echo "Error: missing $VENV_ANSIBLE_VAULT" >&2; exit 1; }

read -rsp "Enter secret for '${SECRET_NAME}': " SECRET_VALUE
echo
if [[ -z "$SECRET_VALUE" ]]; then
  echo "Error: secret cannot be empty." >&2
  exit 1
fi

# Retrieve GPG passphrase from vault non-interactively
GPG_PASSPHRASE="$("$VENV_ANSIBLE_VAULT" view "$VAULT_FILE" --vault-password-file "$VAULT_PASS_FILE" \
  | awk -F': ' '/^app_gpg_passphrase:/ { gsub(/"/,"",$2); printf "%s",$2 }')"

if [[ -z "$GPG_PASSPHRASE" ]]; then
  echo "Error: GPG passphrase not found in vault." >&2
  exit 1
fi

# Encrypt secret (AES-256) directly to output file
printf '%s' "$SECRET_VALUE" | gpg --batch --yes --symmetric --cipher-algo AES256 \
  --passphrase "$GPG_PASSPHRASE" \
  --output "$OUTPUT_FILE"

chmod 0640 "$OUTPUT_FILE"
echo "Encrypted secret saved to: ${OUTPUT_FILE}"
EOF
  sudo install -m 0750 -o "$ADMIN_USER" -g "$ADMIN_GROUP" "$tmp_add" "$ADD_SECRET_SCRIPT"
  rm -f "$tmp_add"
fi

# 7. Initialize Runtime Helpers (System-wide)
echo "--> Initializing Runtime Helpers in /usr/local..."
sudo mkdir -p "$RUNTIME_LIB"

if [[ -f "$REPO_GET_SECRET_SRC" ]]; then
  echo "--> Copying get_secret.sh from repository..."
  sudo install -m 0750 -o "$SERVICE_USER" -g "$SECRET_GROUP" "$REPO_GET_SECRET_SRC" "$GET_SECRET_BASH"
else
  echo "--> Creating get_secret.sh fallback..."
  tmp_get="$(mktemp)"
  chmod 600 "$tmp_get"
  cat > "$tmp_get" <<'EOF'
#!/bin/bash
set -euo pipefail

CREDENTIAL_STORE="/opt/credential_store"
PASSPHRASE_FILE="${CREDENTIAL_STORE}/.gpg_passphrase"

if [[ $# -ne 1 ]]; then
  echo "Usage: get_secret <secret_name>" >&2
  exit 1
fi

SECRET_FILE="${CREDENTIAL_STORE}/${1}_secret.txt.gpg"
gpg --batch --quiet --yes --passphrase-file "$PASSPHRASE_FILE" --decrypt "$SECRET_FILE" 2>/dev/null
EOF
  sudo install -m 0750 -o "$SERVICE_USER" -g "$SECRET_GROUP" "$tmp_get" "$GET_SECRET_BASH"
  rm -f "$tmp_get"
fi

if [[ -f "$REPO_SECURE_APP_SRC" ]]; then
  echo "--> Copying secure-app.sh from repository..."
  # Admin utility; root-owned is fine
  sudo install -m 0755 "$REPO_SECURE_APP_SRC" "$SECURE_APP_BASH"
fi

if [[ -d "$REPO_LIB_SRC" ]]; then
  echo "--> Copying Python helpers from repository directory..."
  sudo rsync -a --delete "$REPO_LIB_SRC/" "$RUNTIME_LIB/"
else
  die "Python helper source directory '${REPO_LIB_SRC}' not found. Run from repo root."
fi

# Set Runtime Permissions (per INSTALLATION.md guidance)
sudo chown -R "${SERVICE_USER}:${SECRET_GROUP}" "$RUNTIME_LIB"
sudo chmod 0750 "$RUNTIME_LIB"
sudo find "$RUNTIME_LIB" -type f -exec chmod 0640 {} +

# Ensure get_secret.sh ownership and permissions
sudo chown "${SERVICE_USER}:${SECRET_GROUP}" "$GET_SECRET_BASH"
sudo chmod 0750 "$GET_SECRET_BASH"

# 8. Finalize Administrative Ownership (avoid accidentally chowning to root)
sudo chown -R "${ADMIN_USER}:${ADMIN_GROUP}" "$BASE_DIR"
sudo find "$BASE_DIR" -type d -exec chmod 0750 {} +

echo "Initialization complete."
echo "--------------------------------------------------------"
echo "Administrative Project: ${BASE_DIR}"
echo "  - venv:              ${VENV_DIR}"
echo "  - vault password:    ${VAULT_PASS_FILE} (0600)"
echo "  - vault file:        ${VAULT_FILE} (0640, encrypted)"
echo "Runtime Helpers:"
echo "  - Bash Helper:       ${GET_SECRET_BASH}"
echo "  - Python Helpers:    ${RUNTIME_LIB}/"
echo "--------------------------------------------------------"

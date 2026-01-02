#!/bin/bash
#
# load_github_identity.sh - Example application script using Ansible Secrets
# to load a GitHub SSH key into the ssh-agent.

# --- PREAMBLE FOR SCRIPTS ---
set -euo pipefail

# --- Configuration ---
# This helper was installed by setup.sh to /usr/local/bin
HELPER_SCRIPT="/usr/local/bin/get_secret.sh"
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_github"

# --- Functions ---

# Cleanup ensures the secret is wiped from memory on exit
cleanup() {
    if [[ -n "${SSH_ASKPASS_SCRIPT:-}" ]]; then
        rm -f "$SSH_ASKPASS_SCRIPT"
    fi
    unset GIT_PASSPHRASE
}

# Trap ensures cleanup happens regardless of how the script ends
trap cleanup EXIT HUP INT QUIT TERM

# --- Retrieval ---

# Retrieve the secret using the runtime helper
# 'gitphrase' corresponds to 'gitphrase_pswd.txt.gpg' in /opt/credential_store
GIT_PASSPHRASE=$("$HELPER_SCRIPT" gitphrase)

if [[ -z "$GIT_PASSPHRASE" ]]; then
    echo "[ERROR] Failed to retrieve GitHub passphrase." >&2
    exit 1
fi

# --- Corrected SSH Agent Logic ---

# 1. Initialize the ssh-agent correctly
# We evaluate the output so SSH_AUTH_SOCK and SSH_AGENT_PID are exported.
eval "$(ssh-agent -s)"

# 2. Add the key using a temporary SSH_ASKPASS helper
# ssh-add requires a helper script to read passwords from variables.
SSH_ASKPASS_SCRIPT=$(mktemp)
cat <<EOF > "$SSH_ASKPASS_SCRIPT"
#!/bin/bash
echo "$GIT_PASSPHRASE"
EOF
chmod 700 "$SSH_ASKPASS_SCRIPT"

# Force ssh-add to use the helper script
export DISPLAY=":0"
export SSH_ASKPASS="$SSH_ASKPASS_SCRIPT"

# The '< /dev/null' forces ssh-add to use the ASKPASS script instead of the TTY.
ssh-add "$SSH_KEY_PATH" < /dev/null

# Clean up the helper immediately after use
rm -f "$SSH_ASKPASS_SCRIPT"

echo "[SUCCESS] GitHub SSH key unlocked and added to agent."


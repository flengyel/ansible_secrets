#!/bin/bash
#
# load_github_identity.sh - Application script using Ansible Secrets
# to load a GitHub SSH key into the ssh-agent efficiently.
#
# This version persists agent information to ~/.ssh/agent.env to allow
# multiple shell sessions to share a single agent process.

# --- PREAMBLE FOR SCRIPTS ---
set -euo pipefail

# --- Configuration ---
HELPER_SCRIPT="/usr/local/bin/get_secret.sh"
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_github"
AGENT_ENV="${HOME}/.ssh/agent.env"

# --- Functions ---

cleanup() {
    if [[ -n "${SSH_ASKPASS_SCRIPT:-}" ]]; then
        rm -f "$SSH_ASKPASS_SCRIPT"
    fi
    unset GIT_PASSPHRASE
}

trap cleanup EXIT HUP INT QUIT TERM

# --- SSH Agent Management ---

# 1. Try to load existing agent environment
if [[ -f "$AGENT_ENV" ]]; then
    source "$AGENT_ENV" > /dev/null
fi

# 2. Check if the agent is actually responsive
if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! ssh-add -l >/dev/null 2>&1; then
    # If the socket is dead or missing, check if an agent process exists
    # but we just lost the environment variables.
    if pgrep -u "$USER" ssh-agent > /dev/null; then
        # Agent exists but we don't know the socket. Kill it to start fresh
        # and stay in sync with our env file.
        pkill -u "$USER" ssh-agent
    fi
    
    # Start a new agent and save the environment
    ssh-agent -s > "$AGENT_ENV"
    source "$AGENT_ENV" > /dev/null
fi

# 3. Check if the specific identity is already loaded
if [[ -f "$SSH_KEY_PATH" ]]; then
    FINGERPRINT=$(ssh-keygen -lf "$SSH_KEY_PATH" | awk '{print $2}')
    if ssh-add -l | grep -q "$FINGERPRINT"; then
        # [INFO] Identity is already loaded. No further action needed.
        exit 0
    fi
fi

# --- Retrieval ---

# If we reached here, the key is not in the agent.
GIT_PASSPHRASE=$("$HELPER_SCRIPT" gitphrase)

if [[ -z "$GIT_PASSPHRASE" ]]; then
    echo "[ERROR] Failed to retrieve GitHub passphrase." >&2
    exit 1
fi

# --- Identity Loading ---

# Load the key using a temporary SSH_ASKPASS helper
SSH_ASKPASS_SCRIPT=$(mktemp)
cat <<EOF > "$SSH_ASKPASS_SCRIPT"
#!/bin/bash
echo "$GIT_PASSPHRASE"
EOF
chmod 700 "$SSH_ASKPASS_SCRIPT"

# Configure the environment to use the helper script
export DISPLAY=":0"
export SSH_ASKPASS="$SSH_ASKPASS_SCRIPT"

# The '< /dev/null' forces ssh-add to use SSH_ASKPASS
ssh-add "$SSH_KEY_PATH" < /dev/null

# Clean up
rm -f "$SSH_ASKPASS_SCRIPT"

echo "[SUCCESS] GitHub identity loaded into ssh-agent (PID: $SSH_AGENT_PID)."


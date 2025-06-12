# Utility & Helper Scripts

This file documents the administrative and helper scripts used to manage and interact with the Ansible Secrets system.

## 1. Administrative Scripts

These scripts are used by administrators to manage the secret deployment process.

## `add-secret.sh`

Purpose: This script securely encrypts and adds a new secret to the Ansible project. It automates the process of creating a GPG-encrypted password file, ensuring the correct GPG passphrase from Ansible Vault is used. This eliminates common errors from manual typos or hidden characters.

Installation:

This script is designed to be run from within the Ansible project directory.

Create the file `/opt/ansible_secrets/add-secret.sh`

Add the source code below to the file.

Make it executable. It should be owned by an administrator (e.g., flengyel).

```bash
sudo chown flengyel:"domain users" /opt/ansible_secrets/add-secret.sh
sudo chmod 750 /opt/ansible_secrets/add-secret.sh
```

Source Code:

```bash
#!/bin/bash
#
# add-secret.sh - A script to securely encrypt and add a new secret
# to the Ansible Secrets project.

set -euo pipefail

# --- Configuration ---
ANSIBLE_PROJECT_DIR="/opt/ansible_secrets"
FILES_DIR="${ANSIBLE_PROJECT_DIR}/files"
VAULT_FILE="${ANSIBLE_PROJECT_DIR}/group_vars/all/vault.yml"
VENV_PATH="${ANSIBLE_PROJECT_DIR}/venv/bin/activate"

# --- Input Validation ---
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <secret_name>" >&2
    echo "Example: $0 mfa_db" >&2
    exit 1
fi

SECRET_NAME="$1"
OUTPUT_FILE="${FILES_DIR}/${SECRET_NAME}_secret.txt.gpg"

if [[ ! -d "$ANSIBLE_PROJECT_DIR" || ! -f "$VAULT_FILE" || ! -f "$VENV_PATH" ]]; then
    echo "Error: Required project files or directories not found in '$ANSIBLE_PROJECT_DIR'." >&2
    exit 1
fi

read -sp "Enter the password for '${SECRET_NAME}': " SECRET_PASSWORD
echo
if [[ -z "$SECRET_PASSWORD" ]]; then
    echo "Error: Password cannot be empty." >&2
    exit 1
fi

if [[ -f "$OUTPUT_FILE" ]]; then
    read -p "Warning: '${OUTPUT_FILE}' already exists. Overwrite? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 1
    fi
fi

# --- Main Logic ---
echo "--> Activating virtual environment..."
source "$VENV_PATH"

echo "--> Retrieving GPG passphrase securely from Ansible Vault..."
GPG_PASSPHRASE=$(ansible-vault view "$VAULT_FILE" | grep 'app_gpg_passphrase:' | awk '{printf "%s", $2}' | tr -d \''"')

if [[ -z "$GPG_PASSPHRASE" ]]; then
    echo "Error: Failed to retrieve GPG passphrase from vault." >&2
    exit 1
fi

echo "--> Encrypting new secret for '${SECRET_NAME}'..."
printf '%s' "$SECRET_PASSWORD" | gpg --batch --yes --symmetric --cipher-algo AES256 \
    --passphrase "$GPG_PASSPHRASE" \
    --output "$OUTPUT_FILE"

if [[ $? -eq 0 ]]; then
    echo "✅ Success! Encrypted secret saved to: ${OUTPUT_FILE}"
    sudo chown service_account:appsecretaccess "$OUTPUT_FILE"
    echo "--> Ownership set to service_account:appsecretaccess"
else
    echo "❌ Error: GPG encryption failed." >&2
    exit 1
fi

deactivate
echo "--> Done."
```

Usage:

Must be run from within the Ansible project directory

```bash
cd /opt/ansible_secrets
./add-secret.sh new_secret_name
```

## `secure-app.sh`

Purpose: This script applies the standard production ownership (service_account:appsecretaccess) and permissions (0750) to an application script. It includes validation to ensure it is only run on `.sh` or `.py` files.

Installation:

This is a general-purpose utility and should be placed in a system-wide binary path.

Create the file `/usr/local/bin/secure-app.sh`

Add the source code below to the file.

Make it executable: 

```bash
sudo chmod 755 /usr/local/bin/secure-app.sh
```

Source Code:

```bash
#!/bin/bash

# --- Input Validation ---
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path_to_script>" >&2
    exit 1
fi

SCRIPT_PATH="$1"

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Error: File not found at '$SCRIPT_PATH'" >&2
    exit 1
fi

extension="${SCRIPT_PATH##*.}"
case "$extension" in
    sh|py)
        echo "Valid extension (.$extension) found. Securing script..."
        ;;
    *)
        echo "Error: Invalid file type. Script only supports '.sh' or '.py' extensions." >&2
        exit 1
        ;;
esac

# --- Main Logic ---
echo "Setting ownership to service_account:appsecretaccess on '$SCRIPT_PATH'"
sudo chown service_account:appsecretaccess "$SCRIPT_PATH"

echo "Setting permissions to 0750 on '$SCRIPT_PATH'"
sudo chmod 0750 "$SCRIPT_PATH"

echo "Done."

Usage
# Must be run by an administrator with sudo privileges.
sudo /usr/local/bin/secure-app.sh /path/to/your/application_script.py
```

## 2. Runtime Helper Modules & Scripts

These are the scripts and modules used by your application scripts at runtime to retrieve secrets and establish connections. They are installed in `/usr/local/lib/ansible_secret_helpers/` and `/usr/local/bin/`.

## `secret_retriever.py`

Purpose: Provides the low-level `get_secret()` function for Python scripts to retrieve secrets. This is the foundation for the other helpers.

Installation:

Create the file /usr/local/lib/ansible_secret_helpers/secret_retriever.py.

Add the source code below.

Set permissions: sudo chmod 0640 /usr/local/lib/ansible_secret_helpers/secret_retriever.py and ensure the parent directory has correct ownership (service_account:appsecretaccess) and permissions (0750).

Source Code:

```python
# /usr/local/lib/ansible_secret_helpers/secret_retriever.py
import os
import subprocess

SECRETS_DIR = "/opt/credential_store"
GPG_PASSPHRASE_FILE = os.path.join(SECRETS_DIR, ".gpg_passphrase")

def get_secret(secret_name: str) -> str:
    """
    Retrieves a decrypted secret for a given secret name.
    Raises RuntimeError on failure.
    """
    # Note the use of the _secret.txt.gpg suffix
    enc_file = os.path.join(SECRETS_DIR, f"{secret_name}_secret.txt.gpg")
    if not os.path.exists(enc_file):
        raise FileNotFoundError(f"Encrypted secret for '{secret_name}' not found.")
    
    cmd = ["gpg", "--batch", "--quiet", "--yes", "--passphrase-file", GPG_PASSPHRASE_FILE, "--decrypt", enc_file]
    
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"GPG decryption failed for '{secret_name}': {e.stderr}")
    except FileNotFoundError:
        raise RuntimeError("gpg command not found. Is GnuPG installed?")
```

## `connection_helpers.py` (New File)

**Purpose:** Provides high-level, reusable functions for establishing database and LDAP connections using secrets from the credential store. Your application scripts should prefer using these functions.

**Installation:**

Create the file `/usr/local/lib/ansible_secret_helpers/connection_helpers.py`.

Add the source code below.

```bash
Set permissions: sudo chmod 0640 /usr/local/lib/ansible_secret_helpers/connection_helpers.py.
```

Source Code:

```python
# /usr/local/lib/ansible_secret_helpers/connection_helpers.py
import sys
import ssl
import sqlalchemy
import cx_Oracle as cx
from ldap3 import Server, Connection, ALL, Tls # Requires ldap3 library
import secret_retriever # Imports the local module

def create_ldap_connection(ldap_server, user_secret, pswd_secret):
    """
    Retrieves credentials and establishes a secure LDAP connection.
    Returns a bound ldap3 Connection object.
    """
    oud_user = None
    oud_pswd = None
    try:
        oud_user = secret_retriever.get_secret(user_secret)
        oud_pswd = secret_retriever.get_secret(pswd_secret)

        tls = Tls(validate=ssl.CERT_NONE)
        srv = Server(ldap_server, port=636, get_info=ALL, use_ssl=True, tls=tls)
        oud = Connection(srv, user=oud_user, password=oud_pswd, auto_bind=True)

        # Clear credentials from memory immediately after use
        oud_user = None
        oud_pswd = None

        if not oud.bound:
            # Use the correct server variable in the error message
            raise ConnectionError(f'Error: cannot bind to {ldap_server}')
        
        # Return the connection object only on success
        return oud

    except Exception as e:
        # Properly handle exceptions and exit
        print(f"Error creating LDAP connection: {e}", file=sys.stderr)
        sys.exit(1)
```


```python
def create_db_connection(dbhost, dbport, dbsid, user_secret, pswd_secret):
    """
    Retrieves credentials from the credential store and creates an Oracle DB connection.
    Returns a tuple of (engine, connection).
    """
    db_user = None
    db_pswd = None
    engine = None
    conn = None
    try:
        db_user = secret_retriever.get_secret(user_secret)
        if not db_user:
            raise RuntimeError(f"Retrieved empty username secret for '{user_secret}'")

        db_pswd = secret_retriever.get_secret(pswd_secret)
        if not db_pswd:
            raise RuntimeError(f"Retrieved empty password for '{pswd_secret}'")

        datasourcename = cx.makedsn(dbhost, dbport, service_name=dbsid)
        connectstring = f'oracle+cx_oracle://{db_user}:{db_pswd}@{datasourcename}'
        
        # Clear credentials from memory immediately after use
        db_user = None
        db_pswd = None
        
        engine = sqlalchemy.create_engine(connectstring, max_identifier_length=128)
        conn = engine.connect()
        return engine, conn

    except Exception as e:
        print(f"Error creating database connection: {e}", file=sys.stderr)
        # Ensure resources are cleaned up on failure
        if conn:
            conn.close()
        if engine:
            engine.dispose()
        sys.exit(1)
```

`get-secret.sh` (for Bash scripts)
(Note the function rename from get_password to get_secret is a Python-specific change, so the Bash script name get_secret.sh remains appropriate and unchanged.)

Purpose: Takes a secret name as an argument and prints the decrypted secret to standard output.

**Installation:**

See INSTALLATION.md for details.
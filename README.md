# Ansible Secrets

Ansible Secrets provides three passwords (LDAP Directory Manager, LDAP read-only, Oracle DB) to Bash and Python scripts without exposing those passwords in plaintext.

## System Components and Directory Structure

Ansible Secrets consists of three security components and relies on a specific directory structure to separate administrative tasks from runtime operations. .

### Directory Definitions

- Application project directories contain the Bash and Python scripts to protect. Those scripts will consume the passwords at runtime but will never contain them.
- Ansible Deployment Project (e.g., `/opt/myapp_ansible_config`). This is a self-contained administrative toolkitused **only** for the setup and maintenance of the secrets. It contains the Ansible playbook, the vault, and thesource GPG-encrypted files. Your application scripts have no knowledge of, and will never interact with, this directory.
- Runtime Secrets Directory (e.g., `/opt/credential_store`).This is the secure, permissions-restricted location on the server where the Ansible playbook places the necessaryfiles for runtime decryption. This is the **single point of interaction** for the application scripts when they need a password.

### Security Components

#### GPG Encryption

This component provides confidentiality for your application passwords. Each password is encrypted with GPG(AES-256 cipher) and the resulting file (e.g., `oracle_db_password.txt.gpg`) is stored in the**Runtime Secrets Directory**. A single, strong GPG passphrase is used to encrypt all three password files.

#### Ansible Vault

This component protects the GPG passphrase. The passphrase--which is the key to unlock all the application passwords--isstored in an encrypted Ansible Vault file that resides within the **Ansible Deployment Project** directory.Access to this vault is controlled by a separate Vault password known only to the administrator.

#### Linux Permissions

This component enforces access control. A dedicated group (`appsecretaccess`) is used to govern who can executethe scripts in your **Application Projects** that require credentials. The permissions on the**Runtime Secrets Directory** are set so that only members of this group can read the encrypted passwords and theGPG passphrase file.

## Deployment and Runtime

The Ansible Secrets implementation has two phases: a one-time setup controlled by Ansible, and the normal runtimeoperation when your scripts execute.

### Phase 1: Deployment (Controlled by Ansible)

This is the administrative process for securely placing the secrets on the server, executed from withinthe **Ansible Deployment Project**. You run an Ansible playbook that performs the following steps:

- Ansible uses its Vault password to decrypt the GPG passphrase in memory.
- It creates the secure **Runtime Secrets Directory** on the server (e.g., `/opt/credential_store`).
- It writes the GPG passphrase from memory into a file within that directory (e.g., `.gpg_passphrase`).
- It copies your three GPG-encrypted password files from the **Ansible Deployment Project** into the **Runtime Secrets Directory**.
- It sets strict ownership and permissions on the **Runtime Secrets Directory** and all its files, granting access only to a dedicated service user (`myappuser`) and the designated group (`appsecretaccess`).

### Runtime Operation (Script Execution)

This is what happens whenever an authorized user runs one of your scripts from an **Application Project**.

- The script starts. It does not interact with the **Ansible Deployment Project** directory.
- The script reads the GPG passphrase from the protected file (`.gpg_passphrase`) inside the **Runtime Secrets Directory** into a variable in memory.
- The script uses this passphrase to decrypt the specific application password it needs from the corresponding file in the **Runtime Secrets Directory** (e.g., `oracle_db_password.txt.gpg`) into a second memory variable.
- It uses the decrypted application password to perform its task (e.g., connect to the Oracle database).
- Once the task is complete, the script immediately clears the variables that held the GPG passphrase and the decrypted application password, minimizing their lifetime in memory. The plaintext application password is never written to disk.

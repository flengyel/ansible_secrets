### **Proposed Directory Names**

Let's replace the generic `myapp` placeholders with these more descriptive names:

1.  **For the Ansible Deployment Project:**
    * **Old Name:** `/opt/myapp_ansible_config`
    * **New Name:** `/opt/ansible_secret_deployment`
        * *Rationale:* This name clearly indicates its purpose (secret deployment) and keeps it within the `/opt` directory, which is appropriate for system-wide administrative tools.

2.  **For the Runtime Secrets Directory:**
    * **Old Name:** `/opt/myapp/secrets`
    * **New Name:** `/opt/credential_store`
        * *Rationale:* "Credential Store" is more descriptive than "secrets." This is the live, runtime location your scripts will use.

3.  **For the Python Helper Library:**
    * **Old Name:** `/opt/myapp/lib`
    * **New Name:** `/usr/local/lib/ansible_secret_helpers`
        * *Rationale:* Placing shared libraries in `/usr/local/lib` is a more standard Linux convention than creating a `lib` directory under `/opt`.

### **How to Implement These Changes**

Changing these names is straightforward. You simply need to substitute the new paths for the old ones in the implementation guide. Here is a checklist of exactly where the changes need to be made:

#### **To Change the Ansible Project Directory:**
From: `/opt/myapp_ansible_config`
To: `/opt/ansible_secret_deployment`

* **Step 1.3 (Project Directory Creation):**
    * Change `sudo mkdir -p /opt/myapp_ansible_config` to `sudo mkdir -p /opt/ansible_secret_deployment`.
    * Change `sudo chown ... /opt/myapp_ansible_config` to `sudo chown ... /opt/ansible_secret_deployment`.
    * All subsequent `cd` commands in the setup instructions must now point to `/opt/ansible_secret_deployment`.

#### **To Change the Runtime Secrets Directory & Python Library Path:**
From: `/opt/myapp/secrets` and `/opt/myapp/lib`
To: `/opt/credential_store` and `/usr/local/lib/ansible_secret_helpers`

1.  **In the Ansible Playbook (`deploy_secrets.yml`):**
    * Update the `secrets_target_dir` variable.
        * **Change:** `secrets_target_dir: "/opt/myapp/secrets"`
        * **To:** `secrets_target_dir: "/opt/credential_store"`

2.  **In the Reusable Bash Script (`/usr/local/bin/get_secret.sh`):**
    * Update the `SECRETS_DIR` variable.
        * **Change:** `SECRETS_DIR="/opt/myapp/secrets"`
        * **To:** `SECRETS_DIR="/opt/credential_store"`

3.  **In the Reusable Python Module (`secret_retriever.py`):**
    * First, place the file in the new standard location:
        * **Old path:** `/opt/myapp/lib/secret_retriever.py`
        * **New path:** `/usr/local/lib/ansible_secret_helpers/secret_retriever.py`
        * (You would need to `sudo mkdir -p /usr/local/lib/ansible_secret_helpers` and set its permissions accordingly).
    * Then, update the `SECRETS_DIR` variable inside the `.py` file itself.
        * **Change:** `SECRETS_DIR = "/opt/myapp/secrets"`
        * **To:** `SECRETS_DIR = "/opt/credential_store"`


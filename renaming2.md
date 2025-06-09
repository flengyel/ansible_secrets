Yes, absolutely. Changing the file naming convention requires updating the configuration in all the places that expect the old names.

Your helper scripts (get\_secret.sh and secret\_retriever.py) are designed to build the filename dynamically, so they have the \_password.txt.gpg suffix hardcoded in them. The Ansible playbook also lists the full filenames to be deployed.

Here is the checklist of exactly what you need to change to align the system with your new \_pswd.txt.gpg naming scheme.

### ---

**Checklist for Updating Filename Convention**

#### **1\. Update the Ansible Playbook (deploy\_secrets.yml)**

You need to change the filenames listed in the encrypted\_secret\_files variable so Ansible knows which files to copy from your ./files directory.

* **Edit:** /opt/ansible\_secrets/deploy\_secrets.yml  
* **Find this section and make the changes:**  
  YAML  
  \# BEFORE  
  vars:  
    \# ...  
    encrypted\_secret\_files:  
      \- ldap\_dm\_password.txt.gpg  
      \- ldap\_ro\_password.txt.gpg  
      \- oracle\_db\_password.txt.gpg

  YAML  
  \# AFTER  
  vars:  
    \# ...  
    encrypted\_secret\_files:  
      \- ldap\_dm\_pswd.txt.gpg  
      \- ldap\_ro\_pswd.txt.gpg  
      \- oracle\_db\_pswd.txt.gpg

#### **2\. Update the Reusable Bash Helper Script (get\_secret.sh)**

You need to change the line where the script constructs the full path to the encrypted file.

* **Edit:** /usr/local/bin/get\_secret.sh  
* **Find this line:**  
  Bash  
  \# BEFORE  
  ENC\_FILE="${SECRETS\_DIR}/${SECRET\_NAME}\_password.txt.gpg"

* **Change it to use the new suffix:**  
  Bash  
  \# AFTER  
  ENC\_FILE="${SECRETS\_DIR}/${SECRET\_NAME}\_pswd.txt.gpg"

#### **3\. Update the Reusable Python Helper Module (secret\_retriever.py)**

Similarly, you need to change the line in the Python function where the filename is constructed.

* **Edit:** /usr/local/lib/ansible\_secret\_helpers/secret\_retriever.py  
* **Find this line within the get\_password function:**  
  Python  
  \# BEFORE  
  enc\_file \= os.path.join(SECRETS\_DIR, f"{secret\_name}\_password.txt.gpg")

* **Change it to use the new suffix:**  
  Python  
  \# AFTER  
  enc\_file \= os.path.join(SECRETS\_DIR, f"{secret\_name}\_pswd.txt.gpg")

---

**Next Step:**

After making these three changes, you should re-run your Ansible playbook to ensure the files with the new names are deployed correctly to /opt/credential\_store.

Bash

cd /opt/ansible\_secrets  
source venv/bin/activate  
ansible-playbook deploy\_secrets.yml

Once you've made these updates, the entire system will be consistent with your new naming convention and will function correctly.
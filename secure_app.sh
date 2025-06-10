#!/bin/bash

# --- Input Validation ---

# 1. Check if exactly one argument was provided.
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path_to_script>" >&2
    exit 1
fi

SCRIPT_PATH="$1"

# 2. Check if the provided path is a regular file that exists.
if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Error: File not found at '$SCRIPT_PATH'" >&2
    exit 1
fi

# 3. Check the file extension.
#    This gets the substring after the last dot.
extension="${SCRIPT_PATH##*.}"

#    Use a case statement to check if the extension is valid.
case "$extension" in
    sh|py)
        # If extension is 'sh' or 'py', continue.
        echo "Valid extension (.$extension) found. Securing script..."
        ;;
    *)
        # If it's anything else, print an error and exit.
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


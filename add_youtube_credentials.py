#!/usr/bin/env python3
"""
YouTube Credentials Helper Script

This script helps you add YouTube OAuth credentials to your api_keys.txt file
for specific projects in your Task Manager app.

Usage:
    python add_youtube_credentials.py <project_name> <client_id> <client_secret>

Example:
    python add_youtube_credentials.py "My Gaming Channel" "123456789-abc123.apps.googleusercontent.com" "GOCSPX-secret123"
"""

import sys
import os

def add_youtube_credentials(project_name, client_id, client_secret):
    """Add YouTube credentials to api_keys.txt file."""
    
    # Create the credential keys
    client_id_key = f"{project_name}_YouTube_Client_ID"
    client_secret_key = f"{project_name}_YouTube_Client_Secret"
    
    # Read existing file
    lines = []
    if os.path.exists('api_keys.txt'):
        with open('api_keys.txt', 'r') as f:
            lines = f.readlines()
    
    # Remove existing credentials for this project if they exist
    lines = [line for line in lines if not (
        line.startswith(f"{client_id_key}=") or 
        line.startswith(f"{client_secret_key}=")
    )]
    
    # Add new credentials
    lines.append(f"{client_id_key}={client_id}\n")
    lines.append(f"{client_secret_key}={client_secret}\n")
    
    # Write back to file
    with open('api_keys.txt', 'w') as f:
        f.writelines(lines)
    
    print(f"✅ YouTube credentials added for project: {project_name}")
    print(f"   Client ID: {client_id}")
    print(f"   Client Secret: {client_secret[:10]}...")
    print(f"   Keys added to api_keys.txt: {client_id_key}, {client_secret_key}")

def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    
    project_name = sys.argv[1]
    client_id = sys.argv[2]
    client_secret = sys.argv[3]
    
    try:
        add_youtube_credentials(project_name, client_id, client_secret)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 
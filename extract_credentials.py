#!/usr/bin/env python3
"""
Simple script to extract OAuth credentials from Google Cloud JSON file
"""

import json
import sys

def extract_credentials(json_file_path):
    """Extract client_id and client_secret from Google Cloud JSON file"""
    try:
        with open(json_file_path, 'r') as f:
            data = json.load(f)
        
        # Handle both 'installed' and 'web' credential types
        if 'installed' in data:
            credentials = data['installed']
        elif 'web' in data:
            credentials = data['web']
        else:
            print("❌ Error: Could not find 'installed' or 'web' section in JSON file")
            return None
        
        client_id = credentials.get('client_id')
        client_secret = credentials.get('client_secret')
        
        if not client_id or not client_secret:
            print("❌ Error: Missing client_id or client_secret in JSON file")
            return None
        
        return {
            'client_id': client_id,
            'client_secret': client_secret
        }
        
    except FileNotFoundError:
        print(f"❌ Error: File '{json_file_path}' not found")
        return None
    except json.JSONDecodeError:
        print("❌ Error: Invalid JSON file")
        return None
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

def main():
    if len(sys.argv) != 2:
        print("Usage: python extract_credentials.py <path_to_json_file>")
        print("Example: python extract_credentials.py ~/Downloads/client_secret_123456.json")
        sys.exit(1)
    
    json_file = sys.argv[1]
    credentials = extract_credentials(json_file)
    
    if credentials:
        # Output in the format expected by the Flutter dialog
        print(f"clientId={credentials['client_id']}")
        print(f"clientSecret={credentials['client_secret']}")
    else:
        sys.exit(1)

if __name__ == "__main__":
    main() 
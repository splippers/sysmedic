#!/usr/bin/env python3
"""
Google OAuth Device Authorization Flow for SysMedic.
Validates user is authenticated via @splippers.com domain.

Usage:
  python3 oauth-device.py <client_id> [--domain splippers.com]
"""

import json
import os
import sys
import time
import urllib.request
import urllib.parse
import urllib.error

DEVICE_CODE_URL = "https://oauth2.googleapis.com/device/code"
TOKEN_URL = "https://oauth2.googleapis.com/token"
USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo"

def json_post(url, data) -> dict:
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=body)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        print(f"\n  [AUTH ERROR] HTTP {e.code}: {err}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"\n  [AUTH ERROR] Network: {e.reason}", file=sys.stderr)
        sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("Usage: oauth-device.py <client_id> [--domain splippers.com]", file=sys.stderr)
        sys.exit(1)

    client_id = sys.argv[1]
    allowed_domain = "splippers.com"
    for i, arg in enumerate(sys.argv[2:]):
        if arg == "--domain" and i + 2 < len(sys.argv):
            allowed_domain = sys.argv[i + 3]

    # Step 1: Get device code
    print()
    print("  ┌──────────────────────────────────────────────┐")
    print("  │       SysMedic · Google OAuth           │")
    print("  ├──────────────────────────────────────────────┤")
    print("  │  Open this URL on your phone or computer:    │")
    print("  │  https://google.com/device                   │")
    print("  ├──────────────────────────────────────────────┤")
    print("  │  Then enter the code below:                  │")
    print("  │                                              │")

    device_resp = json_post(DEVICE_CODE_URL, {
        "client_id": client_id,
        "scope": "openid email profile",
    })

    device_code = device_resp["device_code"]
    user_code = device_resp["user_code"]
    verification_url = device_resp.get("verification_url", "https://google.com/device")
    interval = device_resp.get("interval", 5)
    expires_in = device_resp.get("expires_in", 1800)

    print(f"  │          Code:  \033[1;33m{user_code:>15}\033[0m")
    print(f"  │  URL:  {verification_url}")
    print("  │                                              │")
    print(f"  │  (expires in {expires_in // 60} min · polling every {interval}s)")
    print("  ├──────────────────────────────────────────────┤")
    print("  │  Press Ctrl+C to cancel                      │")
    print("  └──────────────────────────────────────────────┘")
    print()

    # Step 2: Poll for token
    deadline = time.time() + expires_in - 30
    token = None

    while time.time() < deadline:
        time.sleep(interval)
        token_resp = json_post(TOKEN_URL, {
            "client_id": client_id,
            "device_code": device_code,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        })

        if "access_token" in token_resp:
            token = token_resp
            break
        elif token_resp.get("error") == "authorization_pending":
            print("  Waiting for authorization...")
            continue
        elif token_resp.get("error") == "slow_down":
            interval += 5
            continue
        elif token_resp.get("error") in ("access_denied", "expired_token"):
            print(f"\n  [AUTH FAILED] {token_resp['error']}", file=sys.stderr)
            sys.exit(1)
        else:
            print(f"  Waiting... (status: {token_resp.get('error', 'unknown')})")

    if not token:
        print("\n  [AUTH FAILED] Timed out waiting for authorization", file=sys.stderr)
        sys.exit(1)

    # Step 3: Get userinfo
    req = urllib.request.Request(USERINFO_URL)
    req.add_header("Authorization", f"Bearer {token['access_token']}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        userinfo = json.loads(resp.read())

    email = userinfo.get("email", "")
    email_verified = userinfo.get("email_verified", False)
    name = userinfo.get("name", email)

    print(f"\n  Authenticated as: {name} <{email}>")
    if not email_verified:
        print("\n  [AUTH FAILED] Email not verified with Google", file=sys.stderr)
        sys.exit(1)

    # Check domain
    domain = email.split("@")[-1] if "@" in email else ""
    if domain.lower() != allowed_domain.lower():
        print(f"\n  [AUTH FAILED] Domain '{domain}' not allowed. Must be @{allowed_domain}", file=sys.stderr)
        sys.exit(1)

    print(f"  [OK] Domain @{allowed_domain} confirmed")
    print()

    # Output result as JSON for the shell wrapper
    result = {
        "status": "authorized",
        "email": email,
        "name": name,
        "access_token": token["access_token"],
        "expires_in": token.get("expires_in", 3600),
    }
    if "refresh_token" in token:
        result["refresh_token"] = token["refresh_token"]

    print(json.dumps(result))

if __name__ == "__main__":
    main()

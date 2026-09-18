#!/usr/bin/env python3
"""Report enabled Firebase Authentication providers without printing secrets."""

import argparse

from seed_firestore_courts import access_token, request_json


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="backcourt-41720")
    args = parser.parse_args()

    token = access_token()
    base = f"https://identitytoolkit.googleapis.com/admin/v2/projects/{args.project}"
    config = request_json(f"{base}/config", token)
    sign_in = config.get("signIn", {})
    email = sign_in.get("email", {})
    phone = sign_in.get("phoneNumber", {})
    print(f"email/password: {'ENABLED' if email.get('enabled') else 'DISABLED'}")
    print(f"phone: {'ENABLED' if phone.get('enabled') else 'DISABLED'}")

    providers = request_json(
        f"{base}/defaultSupportedIdpConfigs?pageSize=100", token
    ).get("defaultSupportedIdpConfigs", [])
    enabled = sorted(
        provider.get("idpId")
        or provider.get("name", "unknown").rsplit("/", 1)[-1]
        for provider in providers
        if provider.get("enabled")
    )
    print(f"federated providers: {', '.join(enabled) if enabled else 'none'}")


if __name__ == "__main__":
    main()

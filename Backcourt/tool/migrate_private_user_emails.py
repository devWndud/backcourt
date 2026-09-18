#!/usr/bin/env python3
"""Move legacy email fields out of public user profiles without data loss."""

import argparse
from datetime import datetime, timezone

from audit_firestore import collection_documents
from seed_firestore_courts import access_token, request_json


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="backcourt-41720")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    token = access_token()
    users = collection_documents(args.project, token, "users")
    legacy = [user for user in users if "email" in user.get("fields", {})]
    print(f"public email migration targets: {len(legacy)}")
    if not args.apply or not legacy:
        print("preview complete" if not args.apply else "nothing to migrate")
        return

    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    writes = []
    for user in legacy:
        uid = user["name"].rsplit("/", 1)[-1]
        email = user["fields"]["email"]
        private_name = (
            f"projects/{args.project}/databases/(default)/documents/private_users/{uid}"
        )
        writes.extend(
            [
                {
                    "update": {
                        "name": private_name,
                        "fields": {
                            "email": email,
                            "updatedAt": {"timestampValue": timestamp},
                        },
                    },
                    "updateMask": {"fieldPaths": ["email", "updatedAt"]},
                },
                {
                    "update": {"name": user["name"], "fields": {}},
                    "updateMask": {"fieldPaths": ["email"]},
                },
            ]
        )

    request_json(
        (
            f"https://firestore.googleapis.com/v1/projects/{args.project}"
            "/databases/(default)/documents:commit"
        ),
        token,
        method="POST",
        body={"writes": writes},
    )
    print(f"migrated: {len(legacy)}")


if __name__ == "__main__":
    main()

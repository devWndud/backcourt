#!/usr/bin/env python3
"""Read-only integrity audit for Backcourt's top-level Firestore collections."""

import argparse
import urllib.parse

from seed_firestore_courts import access_token, request_json


COLLECTION_FIELDS = {
    "users": {"displayName", "role", "createdAt"},
    "private_users": {"email", "updatedAt"},
    "usernames": {"uid", "createdAt"},
    "courts": {"name", "location", "status"},
    "court_name_requests": {
        "uid",
        "courtId",
        "reportType",
        "status",
        "createdAt",
    },
    "checkins": {
        "uid",
        "courtId",
        "dateKey",
        "monthKey",
        "checkedInAt",
    },
    "active_play_sessions": {"uid", "courtId", "startedAt"},
    "play_sessions": {
        "uid",
        "courtId",
        "startedAt",
        "endedAt",
        "durationMinutes",
    },
    "monthly_play_stats": {
        "uid",
        "courtId",
        "scopeKey",
        "totalMinutes",
        "sessionCount",
    },
    "weekly_play_stats": {
        "uid",
        "courtId",
        "scopeKey",
        "totalMinutes",
        "sessionCount",
    },
    "court_play_stats": {
        "uid",
        "courtId",
        "scopeKey",
        "totalMinutes",
        "sessionCount",
    },
    "reviews": {"uid", "courtId", "checkinId", "rating", "createdAt"},
    "meetups": {
        "createdBy",
        "courtId",
        "startsAt",
        "capacity",
        "participantUids",
    },
    "live_court_statuses": {
        "uid",
        "courtId",
        "activity",
        "playerCount",
        "arrivalUids",
        "expiresAt",
    },
    "posts": {"uid", "courtId", "text", "media", "likeUids", "createdAt"},
}


def collection_documents(project: str, token: str, collection: str) -> list[dict]:
    documents: list[dict] = []
    page_token = ""
    while True:
        query = [("pageSize", "1000")]
        if page_token:
            query.append(("pageToken", page_token))
        url = (
            f"https://firestore.googleapis.com/v1/projects/{project}"
            f"/databases/(default)/documents/{collection}?"
            f"{urllib.parse.urlencode(query)}"
        )
        page = request_json(url, token)
        documents.extend(page.get("documents", []))
        page_token = page.get("nextPageToken", "")
        if not page_token:
            return documents


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="backcourt-41720")
    args = parser.parse_args()

    token = access_token()
    collections: dict[str, list[dict]] = {}
    invalid_total = 0
    for name, required_fields in COLLECTION_FIELDS.items():
        documents = collection_documents(args.project, token, name)
        collections[name] = documents
        invalid = sum(
            not required_fields.issubset(document.get("fields", {}).keys())
            for document in documents
        )
        invalid_total += invalid
        print(f"{name}: {len(documents)} docs / missing-required {invalid}")

    public_emails = sum(
        "email" in document.get("fields", {}) for document in collections["users"]
    )
    print(f"public user email fields: {public_emails}")
    print(f"audit result: {'PASS' if invalid_total == 0 else 'CHECK'}")


if __name__ == "__main__":
    main()

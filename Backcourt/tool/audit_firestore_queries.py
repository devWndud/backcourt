#!/usr/bin/env python3
"""Execute every compound Backcourt Firestore query as a read-only smoke test."""

import argparse
from datetime import datetime, timezone

from seed_firestore_courts import access_token, request_json


def field_filter(field: str, op: str, value: dict) -> dict:
    return {
        "fieldFilter": {
            "field": {"fieldPath": field},
            "op": op,
            "value": value,
        }
    }


def query(collection: str, *, filters: list[dict], order: tuple[str, str] | None = None) -> dict:
    structured: dict = {"from": [{"collectionId": collection}], "limit": 1}
    if len(filters) == 1:
        structured["where"] = filters[0]
    elif filters:
        structured["where"] = {
            "compositeFilter": {"op": "AND", "filters": filters}
        }
    if order:
        structured["orderBy"] = [
            {"field": {"fieldPath": order[0]}, "direction": order[1]}
        ]
    return {"structuredQuery": structured}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="backcourt-41720")
    args = parser.parse_args()

    token = access_token()
    month = datetime.now().strftime("%Y-%m")
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    smoke_queries = {
        "operator court names": query(
            "courts",
            filters=[field_filter("nameSource", "EQUAL", {"stringValue": "operator"})],
        ),
        "court reports": query(
            "court_name_requests", filters=[], order=("createdAt", "DESCENDING")
        ),
        "monthly check-in ranking": query(
            "checkins",
            filters=[field_filter("monthKey", "EQUAL", {"stringValue": month})],
        ),
        "my monthly check-ins": query(
            "checkins",
            filters=[
                field_filter("uid", "EQUAL", {"stringValue": "__audit__"}),
                field_filter("monthKey", "EQUAL", {"stringValue": month}),
            ],
        ),
        "reviews by court": query(
            "reviews",
            filters=[field_filter("courtId", "EQUAL", {"stringValue": "__audit__"})],
            order=("createdAt", "DESCENDING"),
        ),
        "future meetups": query(
            "meetups",
            filters=[field_filter("startsAt", "GREATER_THAN_OR_EQUAL", {"timestampValue": now})],
            order=("startsAt", "ASCENDING"),
        ),
        "active live courts": query(
            "live_court_statuses",
            filters=[field_filter("expiresAt", "GREATER_THAN", {"timestampValue": now})],
            order=("expiresAt", "ASCENDING"),
        ),
        "my posts": query(
            "posts",
            filters=[field_filter("uid", "EQUAL", {"stringValue": "__audit__"})],
            order=("createdAt", "DESCENDING"),
        ),
    }
    for collection in (
        "monthly_play_stats",
        "weekly_play_stats",
        "court_play_stats",
    ):
        smoke_queries[f"{collection} ranking"] = query(
            collection,
            filters=[field_filter("scopeKey", "EQUAL", {"stringValue": "__audit__"})],
            order=("totalMinutes", "DESCENDING"),
        )

    url = (
        f"https://firestore.googleapis.com/v1/projects/{args.project}"
        "/databases/(default)/documents:runQuery"
    )
    for name, body in smoke_queries.items():
        request_json(url, token, method="POST", body=body)
        print(f"{name}: PASS")


if __name__ == "__main__":
    main()

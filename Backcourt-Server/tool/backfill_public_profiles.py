from __future__ import annotations

from firebase_admin import firestore

from app.main import _initialize_firebase


PUBLIC_FIELDS = (
    "displayName",
    "username",
    "bio",
    "photoUrl",
    "position",
    "playStyles",
    "homeCourt",
    "homeCourts",
)


def main() -> None:
    database = _initialize_firebase()
    batch = database.batch()
    pending = 0
    total = 0
    for snapshot in database.collection("users").stream():
        source = snapshot.to_dict() or {}
        public = {
            "uid": snapshot.id,
            "displayName": source.get("displayName") or "새로운 플레이어",
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
        for field in PUBLIC_FIELDS:
            if field in source:
                public[field] = source[field]
        batch.set(
            database.collection("public_profiles").document(snapshot.id),
            public,
            merge=True,
        )
        pending += 1
        total += 1
        if pending == 400:
            batch.commit()
            batch = database.batch()
            pending = 0
    if pending:
        batch.commit()
    print(f"public profiles backfilled: {total}")


if __name__ == "__main__":
    main()

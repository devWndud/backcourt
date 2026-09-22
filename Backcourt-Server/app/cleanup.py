from __future__ import annotations

import hashlib
import logging
import time
from typing import Any, Iterable

import httpx
from firebase_admin import auth, firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from .config import settings


logger = logging.getLogger(__name__)


class MediaCleanupError(RuntimeError):
    pass


def _cloudinary_parts(storage_path: Any) -> tuple[str, str] | None:
    if not isinstance(storage_path, str) or not storage_path.startswith("cloudinary:"):
        return None
    parts = storage_path.split(":", 2)
    if len(parts) != 3 or parts[1] not in {"image", "video", "raw"}:
        return None
    return parts[1], parts[2]


def media_paths(data: dict[str, Any]) -> set[str]:
    values: set[str] = set()
    profile_path = data.get("photoStoragePath")
    if isinstance(profile_path, str):
        values.add(profile_path)
    for item in data.get("media") or []:
        if isinstance(item, dict) and isinstance(item.get("storagePath"), str):
            values.add(item["storagePath"])
    return values


def cloudinary_signature(public_id: str, timestamp: int, api_secret: str) -> str:
    source = f"invalidate=true&public_id={public_id}&timestamp={timestamp}{api_secret}"
    return hashlib.sha1(source.encode("utf-8")).hexdigest()


def destroy_media(paths: Iterable[str]) -> None:
    unique_paths = set(paths)
    if not settings.cloudinary_api_key or not settings.cloudinary_api_secret:
        if unique_paths:
            raise MediaCleanupError(
                "Cloudinary API credentials are required to delete uploaded media"
            )
        return
    for path in unique_paths:
        parsed = _cloudinary_parts(path)
        if parsed is None:
            continue
        resource_type, public_id = parsed
        timestamp = int(time.time())
        signature = cloudinary_signature(
            public_id,
            timestamp,
            settings.cloudinary_api_secret,
        )
        try:
            response = httpx.post(
                f"https://api.cloudinary.com/v1_1/{settings.cloudinary_cloud_name}/"
                f"{resource_type}/destroy",
                data={
                    "public_id": public_id,
                    "timestamp": str(timestamp),
                    "api_key": settings.cloudinary_api_key,
                    "signature": signature,
                    "invalidate": "true",
                },
                timeout=20,
            )
            response.raise_for_status()
        except httpx.HTTPError as error:
            raise MediaCleanupError("Cloudinary media deletion failed") from error


def delete_documents(database: Any, documents: Iterable[Any]) -> None:
    batch = database.batch()
    count = 0
    for document in documents:
        batch.delete(document.reference)
        count += 1
        if count == 400:
            batch.commit()
            batch = database.batch()
            count = 0
    if count:
        batch.commit()


def delete_post(database: Any, uid: str, post_id: str) -> None:
    reference = database.collection("posts").document(post_id)
    snapshot = reference.get()
    if not snapshot.exists:
        return
    data = snapshot.to_dict() or {}
    if str(data.get("uid") or "") != uid:
        raise PermissionError("Post owner mismatch")
    comments = database.collection("comments").where(
        filter=FieldFilter("postId", "==", post_id)
    ).stream()
    delete_documents(database, comments)
    destroy_media(media_paths(data))
    reference.delete()


def delete_account(database: Any, uid: str) -> None:
    media: set[str] = set()
    owned_posts = list(database.collection("posts").where(
        filter=FieldFilter("uid", "==", uid)
    ).stream())
    owned_reviews = list(database.collection("reviews").where(
        filter=FieldFilter("uid", "==", uid)
    ).stream())
    profile_snapshot = database.collection("users").document(uid).get()
    if profile_snapshot.exists:
        media.update(media_paths(profile_snapshot.to_dict() or {}))
    for snapshot in [*owned_posts, *owned_reviews]:
        media.update(media_paths(snapshot.to_dict() or {}))

    # Do not remove the account record while externally hosted personal media
    # is still present. Retrying is safe even if an earlier media item was
    # already destroyed.
    destroy_media(media)

    # Comments on an owned post become unreachable when the post is removed.
    # Delete them explicitly so no orphaned user content remains.
    for post in owned_posts:
        post_comments = database.collection("comments").where(
            filter=FieldFilter("postId", "==", post.id)
        ).stream()
        delete_documents(database, post_comments)

    collections = {
        "posts": ("uid", uid),
        "comments": ("uid", uid),
        "reviews": ("uid", uid),
        "checkins": ("uid", uid),
        "play_sessions": ("uid", uid),
        "monthly_play_stats": ("uid", uid),
        "weekly_play_stats": ("uid", uid),
        "court_play_stats": ("uid", uid),
        "monthly_checkin_stats": ("uid", uid),
        "monthly_court_checkin_stats": ("uid", uid),
        "favorite_courts": ("uid", uid),
        "push_tokens": ("uid", uid),
        "notifications": ("targetUid", uid),
        "notification_events": ("targetUid", uid),
        "content_reports": ("reporterUid", uid),
        "court_name_requests": ("uid", uid),
        "meetups": ("createdBy", uid),
    }
    for collection, (field, value) in collections.items():
        snapshots = database.collection(collection).where(
            filter=FieldFilter(field, "==", value)
        ).stream()
        delete_documents(database, snapshots)

    for collection in ("notifications", "notification_events"):
        snapshots = database.collection(collection).where(
            filter=FieldFilter("actorUid", "==", uid)
        ).stream()
        delete_documents(database, snapshots)

    reports_about_user = database.collection("content_reports").where(
        filter=FieldFilter("targetOwnerUid", "==", uid)
    ).stream()
    delete_documents(database, reports_about_user)

    for field in ("blockerUid", "blockedUid"):
        snapshots = database.collection("blocked_users").where(
            filter=FieldFilter(field, "==", uid)
        ).stream()
        delete_documents(database, snapshots)

    for field in ("followerUid", "followingUid"):
        snapshots = database.collection("follows").where(
            filter=FieldFilter(field, "==", uid)
        ).stream()
        delete_documents(database, snapshots)

    friendships = database.collection("friendships").where(
        filter=FieldFilter("memberUids", "array_contains", uid)
    ).stream()
    delete_documents(database, friendships)

    joined = database.collection("meetups").where(
        filter=FieldFilter("participantUids", "array_contains", uid)
    ).stream()
    for snapshot in joined:
        snapshot.reference.update({
            "participantUids": firestore.ArrayRemove([uid]),
            "updatedAt": firestore.SERVER_TIMESTAMP,
        })

    liked_posts = database.collection("posts").where(
        filter=FieldFilter("likeUids", "array_contains", uid)
    ).stream()
    for snapshot in liked_posts:
        snapshot.reference.update({"likeUids": firestore.ArrayRemove([uid])})

    joined_live_courts = database.collection("live_court_statuses").where(
        filter=FieldFilter("arrivalUids", "array_contains", uid)
    ).stream()
    for snapshot in joined_live_courts:
        snapshot.reference.update({"arrivalUids": firestore.ArrayRemove([uid])})

    username = None
    if profile_snapshot.exists:
        username = (profile_snapshot.to_dict() or {}).get("username")
    database.collection("active_play_sessions").document(uid).delete()
    database.collection("live_court_statuses").document(uid).delete()
    database.collection("private_users").document(uid).delete()
    database.collection("public_profiles").document(uid).delete()
    database.collection("users").document(uid).delete()
    if isinstance(username, str) and username:
        database.collection("usernames").document(username).delete()

    auth.delete_user(uid)

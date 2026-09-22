from __future__ import annotations

import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Any

from firebase_admin import firestore, messaging
from google.cloud.firestore_v1.base_query import FieldFilter


logger = logging.getLogger(__name__)


@firestore.transactional
def _claim_notification(transaction: Any, reference: Any) -> dict[str, Any] | None:
    snapshot = reference.get(transaction=transaction)
    if not snapshot.exists:
        return None
    data = snapshot.to_dict() or {}
    if data.get("pushStatus") != "pending":
        return None
    transaction.update(
        reference,
        {
            "pushStatus": "processing",
            "pushAttemptedAt": firestore.SERVER_TIMESTAMP,
        },
    )
    return data


@firestore.transactional
def _claim_event(transaction: Any, reference: Any) -> dict[str, Any] | None:
    snapshot = reference.get(transaction=transaction)
    if not snapshot.exists:
        return None
    data = snapshot.to_dict() or {}
    if data.get("status") != "pending":
        return None
    transaction.update(
        reference,
        {
            "status": "processing",
            "processingAt": firestore.SERVER_TIMESTAMP,
        },
    )
    return data


class NotificationEventDispatcher:
    """Validates domain events and materializes per-user in-app notifications."""

    def __init__(self, database: Any) -> None:
        self._db = database
        self._watch: Any | None = None
        self._executor = ThreadPoolExecutor(
            max_workers=4,
            thread_name_prefix="backcourt-events",
        )
        self._lock = threading.Lock()
        self._in_flight: set[str] = set()

    def start(self) -> None:
        self._recover_interrupted_jobs()
        query = (
            self._db.collection("notification_events")
            .where(filter=FieldFilter("status", "==", "pending"))
            .limit(200)
        )
        self._watch = query.on_snapshot(self._on_snapshot)
        logger.info("Notification event dispatcher started")

    def stop(self) -> None:
        if self._watch is not None:
            self._watch.unsubscribe()
            self._watch = None
        self._executor.shutdown(wait=False, cancel_futures=True)

    def _recover_interrupted_jobs(self) -> None:
        query = (
            self._db.collection("notification_events")
            .where(filter=FieldFilter("status", "==", "processing"))
            .limit(200)
        )
        batch = self._db.batch()
        recovered = 0
        for snapshot in query.stream():
            batch.update(snapshot.reference, {"status": "pending"})
            recovered += 1
        if recovered:
            batch.commit()
            logger.warning("Recovered %s interrupted notification events", recovered)

    def _on_snapshot(self, snapshots: list[Any], changes: list[Any], _: Any) -> None:
        for change in changes:
            snapshot = change.document
            if (snapshot.to_dict() or {}).get("status") != "pending":
                continue
            with self._lock:
                if snapshot.id in self._in_flight:
                    continue
                self._in_flight.add(snapshot.id)
            self._executor.submit(self._process, snapshot.reference)

    def _process(self, reference: Any) -> None:
        try:
            transaction = self._db.transaction()
            event = _claim_event(transaction, reference)
            if event is None:
                return
            notification, targets = self._resolve_event(event)
            batch = self._db.batch()
            for uid in targets:
                notification_reference = self._db.collection("notifications").document(
                    f"{reference.id}_{uid}"
                )
                batch.set(
                    notification_reference,
                    {
                        **notification,
                        "targetUid": uid,
                        "createdAt": firestore.SERVER_TIMESTAMP,
                        "readAt": None,
                        "pushStatus": "pending",
                    },
                )
            batch.update(
                reference,
                {
                    "status": "delivered",
                    "targetCount": len(targets),
                    "completedAt": firestore.SERVER_TIMESTAMP,
                },
            )
            batch.commit()
        except Exception as error:
            logger.exception("Notification event failed for %s", reference.id)
            try:
                reference.update(
                    {
                        "status": "failed",
                        "error": str(error)[:300],
                        "completedAt": firestore.SERVER_TIMESTAMP,
                    }
                )
            except Exception:
                logger.exception("Could not record event failure for %s", reference.id)
        finally:
            with self._lock:
                self._in_flight.discard(reference.id)

    def _resolve_event(
        self,
        event: dict[str, Any],
    ) -> tuple[dict[str, Any], list[str]]:
        event_type = str(event.get("type") or "")
        actor_uid = str(event.get("actorUid") or "")
        entity_id = str(event.get("entityId") or "")
        court_id = str(event.get("courtId") or "")
        if not actor_uid or not entity_id:
            raise ValueError("Event actorUid or entityId is missing")

        targets: set[str]
        title: str
        body: str
        notification_entity_id = entity_id

        if event_type == "live":
            source = self._document("live_court_statuses", entity_id)
            self._require_source(source, actor_uid, court_id, owner_field="uid")
            targets = self._favorite_uids(court_id)
            activity = {
                "shooting": "슛 연습",
                "playing": "게임 중",
                "looking": "인원 모집",
                "full": "만석",
                "wet": "바닥 젖음",
            }.get(str(source.get("activity")), "코트 LIVE")
            title = "내 코트 LIVE"
            body = f"{source.get('courtName') or '농구 코트'} · {activity} · {int(source.get('playerCount') or 0)}명"
        elif event_type in {"meetup", "meetup_join", "meetup_cancelled"}:
            source = self._document("meetups", entity_id)
            if str(source.get("courtId") or "") != court_id:
                raise ValueError("Meetup court does not match event")
            participants = {str(uid) for uid in source.get("participantUids") or []}
            creator_uid = str(source.get("createdBy") or "")
            if event_type == "meetup":
                if creator_uid != actor_uid or source.get("status") != "open":
                    raise ValueError("Invalid meetup event")
                targets = self._favorite_uids(court_id)
                title = "내 코트에 새 약속"
                body = f"{source.get('courtName') or '농구 코트'} · {source.get('gameType') or '게임'} · {int(source.get('capacity') or 0)}명"
            elif event_type == "meetup_join":
                if actor_uid not in participants or actor_uid == creator_uid:
                    raise ValueError("Invalid meetup join event")
                targets = {creator_uid}
                profile = self._document("users", actor_uid)
                title = "약속 참가"
                body = f"{profile.get('displayName') or '플레이어'}님이 {source.get('courtName') or '농구 코트'} 약속에 참가했어요."
            else:
                if creator_uid != actor_uid or source.get("status") != "cancelled":
                    raise ValueError("Invalid meetup cancellation event")
                targets = participants
                title = "약속 취소"
                body = f"{source.get('courtName') or '농구 코트'} 약속이 취소됐어요."
        elif event_type == "comment":
            source = self._document("comments", entity_id)
            self._require_source(source, actor_uid, court_id, owner_field="uid")
            targets = {str(source.get("postOwnerUid") or "")}
            title = "새 댓글"
            body = f"{source.get('authorName') or '플레이어'} · {source.get('text') or ''}"
            notification_entity_id = str(source.get("postId") or entity_id)
        elif event_type == "follow":
            source = self._document("follows", entity_id)
            follower_uid = str(source.get("followerUid") or "")
            following_uid = str(source.get("followingUid") or "")
            if follower_uid != actor_uid or following_uid == actor_uid:
                raise ValueError("Invalid follow event")
            profile = self._document("users", actor_uid)
            targets = {following_uid}
            title = "새 팔로워"
            body = f"{profile.get('displayName') or '플레이어'}님이 회원님을 팔로우했어요."
        elif event_type in {"friend_request", "friend_accepted"}:
            source = self._document("friendships", entity_id)
            requester_uid = str(source.get("requesterUid") or "")
            target_uid = str(source.get("targetUid") or "")
            profile = self._document("users", actor_uid)
            display_name = str(profile.get("displayName") or "플레이어")
            if event_type == "friend_request":
                if (
                    requester_uid != actor_uid
                    or target_uid == actor_uid
                    or source.get("status") != "pending"
                ):
                    raise ValueError("Invalid friend request event")
                targets = {target_uid}
                title = "친구 요청"
                body = f"{display_name}님이 친구 요청을 보냈어요."
            else:
                if (
                    target_uid != actor_uid
                    or str(source.get("acceptedBy") or "") != actor_uid
                    or source.get("status") != "accepted"
                ):
                    raise ValueError("Invalid friend accepted event")
                targets = {requester_uid}
                title = "친구가 됐어요"
                body = f"{display_name}님과 이제 친구예요."
        elif event_type == "court_report":
            profile = self._document("users", actor_uid)
            if profile.get("role") not in {"admin", "operator"}:
                raise ValueError("Report event actor is not an operator")
            source = self._optional_document("court_name_requests", entity_id)
            target_field = "uid"
            if source is None:
                source = self._document("content_reports", entity_id)
                target_field = "reporterUid"
            if str(source.get("reviewedBy") or "") != actor_uid:
                raise ValueError("Report reviewer does not match event actor")
            targets = {str(source.get(target_field) or "")}
            title = "코트 제보 처리" if target_field == "uid" else "신고 처리"
            status_value = str(source.get("status") or "")
            if target_field == "uid":
                body = {
                    "approved": "제보한 내용이 반영됐어요.",
                    "on_hold": "제보한 내용을 확인 중이에요.",
                    "rejected": "제보한 내용이 반려됐어요.",
                }.get(status_value, "제보 처리가 업데이트됐어요.")
            else:
                body = {
                    "approved": "신고한 콘텐츠가 처리됐어요.",
                    "on_hold": "신고 내용을 확인 중이에요.",
                    "rejected": "신고 검토가 끝났어요.",
                }.get(status_value, "신고 처리가 업데이트됐어요.")
        else:
            raise ValueError(f"Unsupported notification event type: {event_type}")

        targets.discard("")
        targets.discard(actor_uid)
        return (
            {
                "actorUid": actor_uid,
                "type": event_type,
                "title": title[:60],
                "body": body[:300],
                "courtId": court_id or None,
                "entityId": notification_entity_id,
            },
            sorted(targets)[:400],
        )

    def _favorite_uids(self, court_id: str) -> set[str]:
        query = (
            self._db.collection("favorite_courts")
            .where(filter=FieldFilter("courtId", "==", court_id))
            .limit(400)
        )
        targets = {
            str((snapshot.to_dict() or {}).get("uid") or "")
            for snapshot in query.stream()
        }
        home_court_query = (
            self._db.collection("users")
            .where(filter=FieldFilter("homeCourtIds", "array_contains", court_id))
            .limit(400)
        )
        targets.update(snapshot.id for snapshot in home_court_query.stream())
        return targets

    def _document(self, collection: str, document_id: str) -> dict[str, Any]:
        data = self._optional_document(collection, document_id)
        if data is None:
            raise ValueError(f"Missing source document: {collection}/{document_id}")
        return data

    def _optional_document(
        self,
        collection: str,
        document_id: str,
    ) -> dict[str, Any] | None:
        snapshot = self._db.collection(collection).document(document_id).get()
        return (snapshot.to_dict() or {}) if snapshot.exists else None

    @staticmethod
    def _require_source(
        source: dict[str, Any],
        actor_uid: str,
        court_id: str,
        *,
        owner_field: str,
    ) -> None:
        if str(source.get(owner_field) or "") != actor_uid:
            raise ValueError("Event actor does not own source")
        if str(source.get("courtId") or "") != court_id:
            raise ValueError("Event court does not match source")


class PushDispatcher:
    """Consumes Firestore notification outbox records and sends FCM pushes."""

    def __init__(self, database: Any) -> None:
        self._db = database
        self._watch: Any | None = None
        self._executor = ThreadPoolExecutor(
            max_workers=4,
            thread_name_prefix="backcourt-push",
        )
        self._lock = threading.Lock()
        self._in_flight: set[str] = set()

    def start(self) -> None:
        self._recover_interrupted_jobs()
        query = (
            self._db.collection("notifications")
            .where(filter=FieldFilter("pushStatus", "==", "pending"))
            .limit(200)
        )
        self._watch = query.on_snapshot(self._on_snapshot)
        logger.info("Push dispatcher started")

    def stop(self) -> None:
        if self._watch is not None:
            self._watch.unsubscribe()
            self._watch = None
        self._executor.shutdown(wait=False, cancel_futures=True)

    def _recover_interrupted_jobs(self) -> None:
        query = (
            self._db.collection("notifications")
            .where(filter=FieldFilter("pushStatus", "==", "processing"))
            .limit(200)
        )
        batch = self._db.batch()
        recovered = 0
        for snapshot in query.stream():
            batch.update(snapshot.reference, {"pushStatus": "pending"})
            recovered += 1
        if recovered:
            batch.commit()
            logger.warning("Recovered %s interrupted push jobs", recovered)

    def _on_snapshot(self, snapshots: list[Any], changes: list[Any], _: Any) -> None:
        for change in changes:
            snapshot = change.document
            data = snapshot.to_dict() or {}
            if data.get("pushStatus") != "pending":
                continue
            with self._lock:
                if snapshot.id in self._in_flight:
                    continue
                self._in_flight.add(snapshot.id)
            self._executor.submit(self._process, snapshot.reference)

    def _process(self, reference: Any) -> None:
        try:
            transaction = self._db.transaction()
            data = _claim_notification(transaction, reference)
            if data is None:
                return
            self._send(reference, data)
        except Exception as error:
            logger.exception("Push delivery failed for %s", reference.id)
            try:
                reference.update(
                    {
                        "pushStatus": "failed",
                        "pushError": str(error)[:300],
                        "pushCompletedAt": firestore.SERVER_TIMESTAMP,
                    }
                )
            except Exception:
                logger.exception("Could not record push failure for %s", reference.id)
        finally:
            with self._lock:
                self._in_flight.discard(reference.id)

    def _send(self, reference: Any, data: dict[str, Any]) -> None:
        target_uid = str(data.get("targetUid") or "")
        if not target_uid:
            raise ValueError("Notification targetUid is missing")

        token_query = (
            self._db.collection("push_tokens")
            .where(filter=FieldFilter("uid", "==", target_uid))
            .limit(500)
        )
        token_documents = [
            snapshot
            for snapshot in token_query.stream()
            if (snapshot.to_dict() or {}).get("token")
        ]
        if not token_documents:
            reference.update(
                {
                    "pushStatus": "no_devices",
                    "pushCompletedAt": firestore.SERVER_TIMESTAMP,
                }
            )
            return

        tokens = [str(snapshot.to_dict()["token"]) for snapshot in token_documents]
        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(
                title=str(data.get("title") or "빽코트")[:60],
                body=str(data.get("body") or "")[:300],
            ),
            data=self._message_data(reference.id, data),
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="backcourt_activity",
                    sound="default",
                ),
            ),
            apns=messaging.APNSConfig(
                headers={"apns-priority": "10"},
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default", badge=1),
                ),
            ),
        )
        response = messaging.send_each_for_multicast(message)
        invalid_documents = []
        errors: list[str] = []
        for token_document, result in zip(token_documents, response.responses):
            if result.success:
                continue
            error = result.exception
            errors.append(str(error))
            error_name = type(error).__name__.lower()
            if "unregistered" in error_name or "senderidmismatch" in error_name:
                invalid_documents.append(token_document.reference)

        if invalid_documents:
            batch = self._db.batch()
            for token_reference in invalid_documents:
                batch.delete(token_reference)
            batch.commit()

        reference.update(
            {
                "pushStatus": "sent" if response.success_count else "failed",
                "pushSuccessCount": response.success_count,
                "pushFailureCount": response.failure_count,
                "pushError": " | ".join(errors)[:300] if errors else None,
                "pushCompletedAt": firestore.SERVER_TIMESTAMP,
            }
        )

    @staticmethod
    def _message_data(
        notification_id: str,
        data: dict[str, Any],
    ) -> dict[str, str]:
        result = {
            "notificationId": notification_id,
            "type": str(data.get("type") or "live"),
        }
        for key in ("courtId", "entityId", "actorUid"):
            value = data.get(key)
            if value is not None:
                result[key] = str(value)
        return result

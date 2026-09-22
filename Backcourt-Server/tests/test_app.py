from __future__ import annotations

import importlib
import unittest
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.cleanup import cloudinary_signature, media_paths
from app.push import PushDispatcher


class AppTest(unittest.TestCase):
    def test_cloudinary_cleanup_metadata_and_signature(self) -> None:
        self.assertEqual(
            media_paths(
                {
                    "photoStoragePath": "cloudinary:image:profile",
                    "media": [
                        {"storagePath": "cloudinary:video:post"},
                        {"url": "https://example.com/no-path"},
                    ],
                }
            ),
            {"cloudinary:image:profile", "cloudinary:video:post"},
        )
        self.assertEqual(
            cloudinary_signature("folder/file", 123, "secret"),
            "fe73c01d50492d8b4b0af99dcb33da516c50751c",
        )

    def test_health_admin_and_auth_guard(self) -> None:
        module = importlib.import_module("app.main")
        with (
            patch.object(module, "_initialize_firebase", return_value=MagicMock()),
            patch.object(module, "PushDispatcher") as dispatcher_type,
            patch.object(module, "NotificationEventDispatcher") as event_dispatcher_type,
        ):
            dispatcher_type.return_value = MagicMock()
            event_dispatcher_type.return_value = MagicMock()
            with TestClient(module.app) as client:
                self.assertEqual(client.get("/health").json()["status"], "ok")
                site = client.get("/")
                self.assertEqual(site.status_code, 200)
                self.assertIn("일상에서", site.text)
                privacy = client.get("/privacy/")
                self.assertEqual(privacy.status_code, 200)
                self.assertIn("개인정보 처리방침", privacy.text)
                terms = client.get("/terms/")
                self.assertEqual(terms.status_code, 200)
                self.assertIn("이용약관", terms.text)
                deletion = client.get("/delete-account/")
                self.assertEqual(deletion.status_code, 200)
                self.assertIn("계정 및 데이터 삭제", deletion.text)
                admin = client.get("/adminnnn/")
                self.assertEqual(admin.status_code, 200)
                self.assertIn("빽코트 Admin", admin.text)
                unauthorized = client.post(
                    "/api/push/devices",
                    json={"token": "x" * 30, "platform": "android"},
                )
                self.assertEqual(unauthorized.status_code, 401)

    def test_authenticated_device_registration_and_test_push(self) -> None:
        module = importlib.import_module("app.main")
        database = MagicMock()
        token_reference = MagicMock()
        notification_reference = MagicMock()
        notification_reference.id = "notification-1"

        def document(document_id: str | None = None) -> MagicMock:
            return notification_reference if document_id is None else token_reference

        database.collection.return_value.document.side_effect = document
        with (
            patch.object(module, "_initialize_firebase", return_value=database),
            patch.object(module, "PushDispatcher") as dispatcher_type,
            patch.object(module, "NotificationEventDispatcher") as event_dispatcher_type,
        ):
            dispatcher_type.return_value = MagicMock()
            event_dispatcher_type.return_value = MagicMock()
            module.app.dependency_overrides[module.current_user] = lambda: {
                "uid": "user-1"
            }
            try:
                with TestClient(module.app) as client:
                    registered = client.post(
                        "/api/push/devices",
                        json={"token": "x" * 30, "platform": "android"},
                    )
                    self.assertEqual(registered.status_code, 201)
                    token_reference.set.assert_called_once()
                    token_data = token_reference.set.call_args.args[0]
                    self.assertEqual(token_data["uid"], "user-1")
                    self.assertEqual(token_data["platform"], "android")

                    queued = client.post(
                        "/api/push/test",
                        json={"title": "테스트", "body": "연결 확인"},
                    )
                    self.assertEqual(queued.status_code, 202)
                    self.assertEqual(queued.json()["notificationId"], "notification-1")
                    notification_data = notification_reference.set.call_args.args[0]
                    self.assertEqual(notification_data["targetUid"], "user-1")
                    self.assertEqual(notification_data["pushStatus"], "pending")
            finally:
                module.app.dependency_overrides.clear()

    def test_push_payload_contains_route_fields(self) -> None:
        payload = PushDispatcher._message_data(
            "notification-1",
            {
                "type": "comment",
                "courtId": "court-1",
                "entityId": "post-1",
            },
        )
        self.assertEqual(
            payload,
            {
                "notificationId": "notification-1",
                "type": "comment",
                "courtId": "court-1",
                "entityId": "post-1",
            },
        )

    def test_push_without_registered_device_is_completed(self) -> None:
        database = MagicMock()
        database.collection.return_value.where.return_value.limit.return_value.stream.return_value = []
        reference = MagicMock()

        PushDispatcher(database)._send(reference, {"targetUid": "user-1"})

        update = reference.update.call_args.args[0]
        self.assertEqual(update["pushStatus"], "no_devices")

    def test_authenticated_delete_endpoints_use_current_user(self) -> None:
        module = importlib.import_module("app.main")
        database = MagicMock()
        with (
            patch.object(module, "_initialize_firebase", return_value=database),
            patch.object(module, "PushDispatcher") as dispatcher_type,
            patch.object(module, "NotificationEventDispatcher") as event_dispatcher_type,
            patch.object(module, "delete_post") as delete_post,
            patch.object(module, "delete_account") as delete_account,
        ):
            dispatcher_type.return_value = MagicMock()
            event_dispatcher_type.return_value = MagicMock()
            module.app.dependency_overrides[module.current_user] = lambda: {
                "uid": "user-1"
            }
            try:
                with TestClient(module.app) as client:
                    post_result = client.delete("/api/posts/post-1")
                    self.assertEqual(post_result.status_code, 200)
                    delete_post.assert_called_once_with(database, "user-1", "post-1")

                    account_result = client.delete("/api/account")
                    self.assertEqual(account_result.status_code, 200)
                    delete_account.assert_called_once_with(database, "user-1")
            finally:
                module.app.dependency_overrides.clear()


if __name__ == "__main__":
    unittest.main()

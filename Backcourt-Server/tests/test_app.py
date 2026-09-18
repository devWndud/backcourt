from __future__ import annotations

import importlib
import unittest
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.push import PushDispatcher


class AppTest(unittest.TestCase):
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
                admin = client.get("/")
                self.assertEqual(admin.status_code, 200)
                self.assertIn("빽코트 Admin", admin.text)
                unauthorized = client.post(
                    "/api/push/devices",
                    json={"token": "x" * 30, "platform": "android"},
                )
                self.assertEqual(unauthorized.status_code, 401)

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


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import hashlib
import logging
from contextlib import asynccontextmanager
from typing import Annotated, Any, Literal

import firebase_admin
from fastapi import Depends, FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from firebase_admin import firestore
from pydantic import BaseModel, Field

from .config import settings
from .push import NotificationEventDispatcher, PushDispatcher
from .security import current_user


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)


class DeviceRegistration(BaseModel):
    token: str = Field(min_length=20, max_length=4096)
    platform: Literal["ios", "android"]


class DeviceRemoval(BaseModel):
    token: str = Field(min_length=20, max_length=4096)


class PushTestRequest(BaseModel):
    title: str = Field(default="빽코트 테스트", min_length=1, max_length=60)
    body: str = Field(default="푸시 연결 완료 🏀", min_length=1, max_length=300)


def _initialize_firebase() -> Any:
    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={"projectId": settings.project_id})
    return firestore.client()


@asynccontextmanager
async def lifespan(app: FastAPI):
    database = _initialize_firebase()
    event_dispatcher = NotificationEventDispatcher(database)
    dispatcher = PushDispatcher(database)
    event_dispatcher.start()
    dispatcher.start()
    app.state.database = database
    app.state.push_dispatcher = dispatcher
    app.state.notification_event_dispatcher = event_dispatcher
    yield
    dispatcher.stop()
    event_dispatcher.stop()


app = FastAPI(
    title="Backcourt API",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
)

if settings.allowed_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.allowed_origins),
        allow_credentials=True,
        allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )


def _database(request: Request) -> Any:
    return request.app.state.database


def _token_id(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "backcourt"}


@app.post("/api/push/devices", status_code=status.HTTP_201_CREATED)
def register_device(
    registration: DeviceRegistration,
    user: Annotated[dict[str, Any], Depends(current_user)],
    database: Annotated[Any, Depends(_database)],
) -> dict[str, str]:
    uid = str(user["uid"])
    reference = database.collection("push_tokens").document(
        _token_id(registration.token)
    )
    reference.set(
        {
            "uid": uid,
            "token": registration.token,
            "platform": registration.platform,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )
    return {"status": "registered"}


@app.delete("/api/push/devices")
def unregister_device(
    removal: DeviceRemoval,
    user: Annotated[dict[str, Any], Depends(current_user)],
    database: Annotated[Any, Depends(_database)],
) -> dict[str, str]:
    reference = database.collection("push_tokens").document(_token_id(removal.token))
    snapshot = reference.get()
    if snapshot.exists and (snapshot.to_dict() or {}).get("uid") == user["uid"]:
        reference.delete()
    return {"status": "removed"}


@app.post("/api/push/test", status_code=status.HTTP_202_ACCEPTED)
def test_push(
    payload: PushTestRequest,
    user: Annotated[dict[str, Any], Depends(current_user)],
    database: Annotated[Any, Depends(_database)],
) -> dict[str, str]:
    reference = database.collection("notifications").document()
    reference.set(
        {
            "targetUid": user["uid"],
            "actorUid": user["uid"],
            "type": "live",
            "title": payload.title,
            "body": payload.body,
            "courtId": None,
            "entityId": None,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "readAt": None,
            "pushStatus": "pending",
        }
    )
    return {"status": "queued", "notificationId": reference.id}


if settings.admin_static_dir.is_dir():
    app.mount(
        "/",
        StaticFiles(directory=settings.admin_static_dir, html=True),
        name="admin-console",
    )

from __future__ import annotations

import math
from collections import defaultdict
from typing import Any

import firebase_admin
from firebase_admin import firestore

from .config import settings


CELL_SIZE = 0.05


def geo_cell(location: Any) -> str | None:
    latitude = getattr(location, "latitude", None)
    longitude = getattr(location, "longitude", None)
    if not isinstance(latitude, (int, float)) or not isinstance(longitude, (int, float)):
        return None
    return f"{math.floor(latitude / CELL_SIZE)}_{math.floor(longitude / CELL_SIZE)}"


def commit_updates(database: Any, updates: list[tuple[Any, dict[str, Any]]]) -> None:
    for start in range(0, len(updates), 400):
        batch = database.batch()
        for reference, data in updates[start : start + 400]:
            batch.set(reference, data, merge=True)
        batch.commit()


def run() -> None:
    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={"projectId": settings.project_id})
    database = firestore.client()
    updates: list[tuple[Any, dict[str, Any]]] = []

    for collection in ("posts", "live_court_statuses"):
        for snapshot in database.collection(collection).stream():
            data = snapshot.to_dict() or {}
            cell = geo_cell(data.get("location"))
            if cell and data.get("geoCell") != cell:
                updates.append((snapshot.reference, {"geoCell": cell}))

    for snapshot in database.collection("users").stream():
        data = snapshot.to_dict() or {}
        home_courts = data.get("homeCourts") or []
        ids = [str(item.get("id")) for item in home_courts if isinstance(item, dict) and item.get("id")]
        if not ids and isinstance(data.get("homeCourt"), dict) and data["homeCourt"].get("id"):
            ids = [str(data["homeCourt"]["id"])]
        if ids != data.get("homeCourtIds"):
            updates.append((snapshot.reference, {"homeCourtIds": ids}))

    monthly: dict[tuple[str, str], dict[str, Any]] = defaultdict(lambda: {"count": 0})
    court_monthly: dict[tuple[str, str, str], dict[str, Any]] = defaultdict(lambda: {"count": 0})
    for snapshot in database.collection("checkins").stream():
        data = snapshot.to_dict() or {}
        uid = str(data.get("uid") or "")
        month = str(data.get("monthKey") or "")
        court_id = str(data.get("courtId") or "")
        if not uid or not month or not court_id:
            continue
        global_entry = monthly[(month, uid)]
        global_entry.update({
            "uid": uid,
            "displayName": data.get("displayName") or "플레이어",
            "scopeKey": month,
            "monthKey": month,
            "lastCheckinId": snapshot.id,
            "updatedAt": firestore.SERVER_TIMESTAMP,
            "count": int(global_entry["count"]) + 1,
        })
        court_key = f"{month}_{court_id}"
        court_entry = court_monthly[(month, court_id, uid)]
        court_entry.update({
            "uid": uid,
            "displayName": data.get("displayName") or "플레이어",
            "scopeKey": court_key,
            "monthKey": month,
            "courtId": court_id,
            "courtName": data.get("courtName") or "농구 코트",
            "lastCheckinId": snapshot.id,
            "updatedAt": firestore.SERVER_TIMESTAMP,
            "count": int(court_entry["count"]) + 1,
        })

    for (month, uid), data in monthly.items():
        updates.append((database.collection("monthly_checkin_stats").document(f"{month}_{uid}"), data))
    for (month, court_id, uid), data in court_monthly.items():
        updates.append((database.collection("monthly_court_checkin_stats").document(f"{month}_{court_id}_{uid}"), data))

    updates.append((database.collection("app_config").document("release"), {
        "maintenanceEnabled": False,
        "maintenanceMessage": "잠시 후 다시 접속해주세요.",
        "maintenanceEndsAt": None,
        "minIosVersion": "1.0.0",
        "latestIosVersion": "1.0.0",
        "iosStoreUrl": "",
        "minAndroidVersion": "1.0.0",
        "latestAndroidVersion": "1.0.0",
        "androidStoreUrl": "https://play.google.com/store/apps/details?id=kr.backcourt.backcourt",
        "updateMessage": "새로운 버전의 빽코트로 업데이트해주세요.",
        "updatedAt": firestore.SERVER_TIMESTAMP,
        "updatedBy": "migration",
    }))

    commit_updates(database, updates)
    print(f"migration complete: {len(updates)} writes")


if __name__ == "__main__":
    run()

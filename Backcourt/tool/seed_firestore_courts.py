#!/usr/bin/env python3
"""Idempotently seed the bundled OSM court catalog into Cloud Firestore."""

import argparse
import hashlib
import json
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import certifi


FIREBASE_SCOPE = "https://www.googleapis.com/auth/cloud-platform"
UNNAMED_COURT = "이름 없는 농구 코트"
SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())


def firebase_cli_credentials() -> tuple[str, str, str]:
    home = Path.home()
    config_path = home / ".config/configstore/firebase-tools.json"
    api_path = (
        home
        / ".cache/firebase/tools/lib/node_modules/firebase-tools/lib/api.js"
    )
    if not config_path.exists() or not api_path.exists():
        raise RuntimeError("Firebase CLI 로그인 정보가 없습니다. firebase login을 먼저 실행해주세요.")

    config = json.loads(config_path.read_text())
    refresh_token = config.get("tokens", {}).get("refresh_token")
    source = api_path.read_text()
    client_id_match = re.search(r'FIREBASE_CLIENT_ID", "([^"]+)', source)
    secret_match = re.search(r'FIREBASE_CLIENT_SECRET", "([^"]+)', source)
    if not refresh_token or not client_id_match or not secret_match:
        raise RuntimeError("Firebase CLI 인증 정보를 읽지 못했습니다.")
    return refresh_token, client_id_match.group(1), secret_match.group(1)


def access_token() -> str:
    refresh_token, client_id, client_secret = firebase_cli_credentials()
    payload = urllib.parse.urlencode(
        {
            "refresh_token": refresh_token,
            "client_id": client_id,
            "client_secret": client_secret,
            "grant_type": "refresh_token",
            "scope": FIREBASE_SCOPE,
        }
    ).encode()
    request = urllib.request.Request(
        "https://www.googleapis.com/oauth2/v3/token",
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(request, context=SSL_CONTEXT) as response:
        token = json.load(response).get("access_token")
    if not token:
        raise RuntimeError("Firebase 접근 토큰을 가져오지 못했습니다.")
    return token


def request_json(
    url: str,
    token: str,
    *,
    method: str = "GET",
    body: dict | None = None,
) -> dict:
    data = json.dumps(body, ensure_ascii=False).encode() if body else None
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, context=SSL_CONTEXT) as response:
            content = response.read()
            return json.loads(content) if content else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:500]
        raise RuntimeError(f"Firestore API {error.code}: {detail}") from error


def fact_labels(properties: dict) -> list[str]:
    result: list[str] = []
    if properties.get("indoor") == "yes":
        result.append("실내")
    elif properties.get("covered") == "yes":
        result.append("지붕 있음")
    else:
        result.append("야외")
    for key, yes, no in [
        ("lit", "조명 있음", "조명 없음"),
        ("fee", "유료", "무료"),
    ]:
        if properties.get(key) == "yes":
            result.append(yes)
        elif properties.get(key) == "no":
            result.append(no)
    if properties.get("surface"):
        result.append(f"바닥 {properties['surface']}")
    if properties.get("hoops"):
        result.append(f"골대 {properties['hoops']}개")
    if properties.get("opening_hours"):
        result.append(f"운영 {properties['opening_hours']}")
    return result


def stable_name(properties: dict) -> tuple[str, str]:
    supplied = str(properties.get("name") or "").strip()
    if supplied and supplied != UNNAMED_COURT:
        return supplied, str(properties.get("name_source") or "openstreetmap")
    address = str(properties.get("address") or "").strip()
    for part in reversed(address.split()):
        if re.search(r"(동|읍|면|리|구|시|군)$", part):
            return f"{part} 농구장", "address_fallback"
    return "지역 농구장", "generated"


def normalize(feature: dict, catalog_version: str) -> dict:
    properties = feature.get("properties", {})
    coordinates = feature.get("geometry", {}).get("coordinates", [])
    osm_type = str(properties.get("osm_type") or "feature")
    osm_id = int(properties.get("osm_id") or feature["id"])
    name, name_source = stable_name(properties)
    raw = {
        "name": name,
        "nameSource": name_source,
        "latitude": float(coordinates[1]),
        "longitude": float(coordinates[0]),
        "address": properties.get("address"),
        "facts": fact_labels(properties),
        "source": "openstreetmap",
        "sourceUrl": properties.get("source_url")
        or f"https://www.openstreetmap.org/{osm_type}/{osm_id}",
        "status": "active",
        "osmType": osm_type,
        "osmId": osm_id,
        "verified": properties.get("verified") is True,
        "access": properties.get("access"),
        "surface": properties.get("surface"),
        "lit": properties.get("lit"),
        "hoops": properties.get("hoops"),
        "indoor": properties.get("indoor"),
        "covered": properties.get("covered"),
        "fee": properties.get("fee"),
        "openingHours": properties.get("opening_hours"),
        "operatorName": properties.get("operator"),
        "administrativeName": properties.get("administrative_name"),
        "administrativeNameEnglish": properties.get("administrative_name_eng"),
        "administrativeCode": properties.get("administrative_code"),
        "administrativeBaseYear": properties.get("administrative_base_year"),
        "administrativeMatch": properties.get("administrative_match"),
        "catalogVersion": catalog_version,
    }
    fingerprint_source = json.dumps(
        raw, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode()
    return {
        "id": f"osm_{osm_type}_{osm_id}",
        "raw": raw,
        "catalogFingerprint": hashlib.sha256(fingerprint_source).hexdigest(),
    }


def text(value: object) -> dict:
    return {"stringValue": str(value)}


def nullable_text(value: object | None) -> dict:
    return {"nullValue": None} if value is None else text(value)


def firestore_fields(court: dict) -> dict:
    raw = court["raw"]
    return {
        "name": text(raw["name"]),
        "nameSource": text(raw["nameSource"]),
        "location": {
            "geoPointValue": {
                "latitude": raw["latitude"],
                "longitude": raw["longitude"],
            }
        },
        "address": nullable_text(raw["address"]),
        "facts": {"arrayValue": {"values": [text(item) for item in raw["facts"]]}},
        "source": text(raw["source"]),
        "sourceUrl": text(raw["sourceUrl"]),
        "status": text(raw["status"]),
        "osmType": text(raw["osmType"]),
        "osmId": {"integerValue": str(raw["osmId"])},
        "verified": {"booleanValue": raw["verified"]},
        "access": nullable_text(raw["access"]),
        "surface": nullable_text(raw["surface"]),
        "lit": nullable_text(raw["lit"]),
        "hoops": nullable_text(raw["hoops"]),
        "indoor": nullable_text(raw["indoor"]),
        "covered": nullable_text(raw["covered"]),
        "fee": nullable_text(raw["fee"]),
        "openingHours": nullable_text(raw["openingHours"]),
        "operatorName": nullable_text(raw["operatorName"]),
        "administrativeName": nullable_text(raw["administrativeName"]),
        "administrativeNameEnglish": nullable_text(
            raw["administrativeNameEnglish"]
        ),
        "administrativeCode": nullable_text(raw["administrativeCode"]),
        "administrativeBaseYear": nullable_text(raw["administrativeBaseYear"]),
        "administrativeMatch": nullable_text(raw["administrativeMatch"]),
        "catalogVersion": text(raw["catalogVersion"]),
        "catalogFingerprint": text(court["catalogFingerprint"]),
        "catalogUpdatedAt": {
            "timestampValue": datetime.now(timezone.utc).isoformat()
        },
    }


def read_string(fields: dict, key: str) -> str | None:
    return fields.get(key, {}).get("stringValue")


def existing_courts(project: str, token: str) -> dict[str, dict]:
    result: dict[str, dict] = {}
    page_token = ""
    while True:
        query = [
            ("pageSize", "1000"),
            ("mask.fieldPaths", "name"),
            ("mask.fieldPaths", "nameSource"),
            ("mask.fieldPaths", "status"),
            ("mask.fieldPaths", "catalogFingerprint"),
        ]
        if page_token:
            query.append(("pageToken", page_token))
        url = (
            f"https://firestore.googleapis.com/v1/projects/{project}"
            f"/databases/(default)/documents/courts?{urllib.parse.urlencode(query)}"
        )
        page = request_json(url, token)
        for document in page.get("documents", []):
            fields = document.get("fields", {})
            result[document["name"].rsplit("/", 1)[-1]] = {
                "name": read_string(fields, "name"),
                "nameSource": read_string(fields, "nameSource"),
                "status": read_string(fields, "status"),
                "catalogFingerprint": read_string(fields, "catalogFingerprint"),
            }
        page_token = page.get("nextPageToken", "")
        if not page_token:
            return result


def commit(project: str, token: str, courts: list[dict], existing: dict) -> None:
    writes = []
    for court in courts:
        fields = firestore_fields(court)
        if existing.get(court["id"], {}).get("nameSource") == "operator":
            fields.pop("name")
            fields.pop("nameSource")
        if existing.get(court["id"], {}).get("status") in {"closed", "duplicate"}:
            fields.pop("status")
        writes.append(
            {
                "update": {
                    "name": (
                        f"projects/{project}/databases/(default)/documents"
                        f"/courts/{court['id']}"
                    ),
                    "fields": fields,
                },
                "updateMask": {"fieldPaths": list(fields)},
            }
        )
    request_json(
        (
            f"https://firestore.googleapis.com/v1/projects/{project}"
            "/databases/(default)/documents:commit"
        ),
        token,
        method="POST",
        body={"writes": writes},
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="backcourt-41720")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    catalog_path = Path("assets/data/korea_basketball_courts.geojson")
    catalog = json.loads(catalog_path.read_text())
    catalog_version = str(catalog.get("metadata", {}).get("generated_at", "unknown"))
    courts = [normalize(feature, catalog_version) for feature in catalog["features"]]
    if len({court["id"] for court in courts}) != len(courts):
        raise RuntimeError("중복된 OSM 코트 ID가 있습니다.")

    token = access_token()
    existing = existing_courts(args.project, token)
    pending = [
        court
        for court in courts
        if existing.get(court["id"], {}).get("catalogFingerprint")
        != court["catalogFingerprint"]
    ]
    legacy_count = sum(not court_id.startswith("osm_") for court_id in existing)
    print(
        f"카탈로그 {len(courts)}개 / 기존 {len(existing)}개 / "
        f"반영 대상 {len(pending)}개"
    )
    if legacy_count:
        print(f"기존 순번 ID 문서 {legacy_count}개는 안전하게 보존합니다.")
    if not args.apply:
        print("미리보기 완료. 실제 반영은 --apply 옵션을 사용하세요.")
        return

    batch_size = 400
    for start in range(0, len(pending), batch_size):
        batch = pending[start : start + batch_size]
        commit(args.project, token, batch, existing)
        print(f"{min(start + len(batch), len(pending))}/{len(pending)} 반영")
    print(f"Firestore courts 컬렉션 시딩 완료: {len(pending)}개 반영")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # noqa: BLE001 - CLI must return a concise failure.
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from error

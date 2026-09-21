#!/usr/bin/env python3
"""Seed reversible demo activity for Cheonan City Hall basketball court.

The script uses deterministic document IDs and tags every created document with
``cheonan_cityhall_demo_v1``. Running ``--apply`` again refreshes the same demo
data instead of creating duplicates. ``--cleanup`` removes only tagged data.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

import firebase_admin
from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter


SEED_TAG = "cheonan_cityhall_demo_v1"
COURT_NAME = "천안시청 농구장"
SEOUL = ZoneInfo("Asia/Seoul")


USERS = [
    {
        "uid": "demo_cheonan_01",
        "displayName": "민수",
        "username": "bc_minsu23",
        "bio": "평일 저녁에 주로 뜁니다",
        "birthYear": 1997,
        "position": "guard",
        "playStyles": ["passing", "shooting"],
    },
    {
        "uid": "demo_cheonan_02",
        "displayName": "준호",
        "username": "bc_junho11",
        "bio": "슛보다 패스 좋아함",
        "birthYear": 1994,
        "position": "forward",
        "playStyles": ["passing", "defense"],
    },
    {
        "uid": "demo_cheonan_03",
        "displayName": "도윤",
        "username": "doyoon_ball",
        "bio": "천안에서 농구 시작한 지 2년",
        "birthYear": 2001,
        "position": "guard",
        "playStyles": ["drive", "passing"],
    },
    {
        "uid": "demo_cheonan_04",
        "displayName": "재현",
        "username": "jaehyun_04",
        "bio": "퇴근하고 한 게임",
        "birthYear": 1996,
        "position": "forward",
        "playStyles": ["shooting", "rebound"],
    },
    {
        "uid": "demo_cheonan_05",
        "displayName": "성민",
        "username": "sungmin_c",
        "bio": "주말 오후 고정",
        "birthYear": 1992,
        "position": "center",
        "playStyles": ["rebound", "defense"],
    },
    {
        "uid": "demo_cheonan_06",
        "displayName": "현우",
        "username": "hyunwoo_pg",
        "bio": "3대3 좋아합니다",
        "birthYear": 1999,
        "position": "guard",
        "playStyles": ["drive", "shooting"],
    },
    {
        "uid": "demo_cheonan_07",
        "displayName": "지훈",
        "username": "jihoon_11",
        "bio": "수비 열심히 합니다",
        "birthYear": 1995,
        "position": "forward",
        "playStyles": ["defense", "rebound"],
    },
    {
        "uid": "demo_cheonan_08",
        "displayName": "태윤",
        "username": "taeyoon_hoop",
        "bio": "혼자 슛하러 자주 와요",
        "birthYear": 2002,
        "position": "guard",
        "playStyles": ["shooting", "drive"],
    },
    {
        "uid": "demo_cheonan_09",
        "displayName": "승재",
        "username": "seungjae_7",
        "bio": "농구는 재밌게",
        "birthYear": 1998,
        "position": "forward",
        "playStyles": ["passing", "rebound"],
    },
    {
        "uid": "demo_cheonan_10",
        "displayName": "동현",
        "username": "donghyun_32",
        "bio": "천안 코트 돌아다니는 중",
        "birthYear": 1993,
        "position": "center",
        "playStyles": ["rebound", "defense", "passing"],
    },
]


POSTS = [
    "오늘 저녁 8시쯤 두 명 갑니다. 공은 챙겨갈게요",
    "지금 반코트 쪽 5명 있어요. 한두 분 더 오시면 게임 가능할 듯",
    "바닥 거의 말랐는데 골대 밑만 살짝 미끄럽습니다",
    "평일 9시 이후에도 조명 켜져 있나요? 퇴근하고 가보려는데",
    "이번 주 토요일 4시쯤 3대3 하실 분 구해요. 혼자 오셔도 됩니다",
    "오늘 처음 와봤는데 생각보다 코트 넓고 괜찮네요",
    "한쪽 그물 조금 늘어져 있어요. 게임하는 데는 문제 없습니다",
    "저녁에 자주 나오시는 분들 계시면 같이 뛰어요. 너무 빡겜 말고 재밌게",
    "공 하나 챙겨왔습니다. 슛만 하다가 인원 되면 게임해요",
    "주말 오후엔 보통 몇 명 정도 나오나요? 이번에 가보려고요",
]


COMMENTS = [
    (0, 2, "저 8시 반쯤 도착합니다"),
    (0, 6, "저도 한 명 같이 갈게요"),
    (1, 8, "조금 있다가 갑니다"),
    (2, 0, "오 감사합니다"),
    (3, 4, "지난번엔 9시 반까지 켜져 있었어요"),
    (4, 7, "저 참가할게요"),
    (4, 9, "초보도 괜찮나요?"),
    (4, 4, "네 편하게 오셔도 됩니다"),
    (9, 1, "7시 넘으면 조금씩 모이더라고요"),
]


ALL_MINUTES = [2380, 1965, 1710, 1490, 1285, 1090, 875, 690, 520, 365]
MONTH_MINUTES = [830, 745, 660, 590, 515, 440, 365, 290, 220, 145]
WEEK_MINUTES = [185, 160, 145, 125, 110, 95, 80, 65, 45, 30]
ALL_SESSIONS = [31, 27, 24, 22, 19, 17, 14, 12, 9, 7]
MONTH_SESSIONS = [11, 10, 9, 8, 7, 7, 6, 5, 4, 3]
WEEK_SESSIONS = [3, 3, 3, 2, 2, 2, 2, 1, 1, 1]


def date_key(value: datetime) -> str:
    return value.strftime("%Y-%m-%d")


def month_key(value: datetime) -> str:
    return value.strftime("%Y-%m")


def week_key(value: datetime) -> str:
    monday = value.date() - timedelta(days=value.weekday())
    return monday.isoformat()


def next_weekday_at(now: datetime, weekday: int, hour: int, minute: int = 0) -> datetime:
    days = (weekday - now.weekday()) % 7
    candidate = datetime.combine(now.date() + timedelta(days=days), time(hour, minute), SEOUL)
    if candidate <= now:
        candidate += timedelta(days=7)
    return candidate


def init_firestore():
    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    return firestore.client()


def find_court(db):
    docs = list(
        db.collection("courts")
        .where(filter=FieldFilter("name", "==", COURT_NAME))
        .limit(2)
        .stream()
    )
    if len(docs) != 1:
        raise RuntimeError(f"'{COURT_NAME}' 문서를 하나만 찾을 수 있어야 합니다. 현재 {len(docs)}개")
    data = docs[0].to_dict()
    location = data.get("location")
    if not isinstance(location, firestore.GeoPoint):
        raise RuntimeError("코트 location 필드가 없습니다.")
    return docs[0].id, data, location


def build_seed(db, now: datetime):
    court_id, court, location = find_court(db)
    court_name = court.get("name", COURT_NAME)
    home_court = {
        "id": court_id,
        "name": court_name,
        "location": location,
        "address": court.get("address"),
        "facts": court.get("facts", []),
    }
    user_ids = [user["uid"] for user in USERS]
    post_comment_counts = Counter(post_index for post_index, _, _ in COMMENTS)
    meetup_creator_counts = Counter([0, 3, 5, 8])
    documents: list[tuple[str, str, dict]] = []

    for index, user in enumerate(USERS):
        uid = user["uid"]
        documents.append(
            (
                "users",
                uid,
                {
                    **user,
                    "role": "user",
                    "photoUrl": None,
                    "checkinCount": ALL_SESSIONS[index],
                    "postCount": 1,
                    "meetupCount": meetup_creator_counts[index],
                    "liveCourtCount": 1 if index < 4 else 0,
                    "onboardingComplete": True,
                    "homeCourt": home_court,
                    "createdAt": now - timedelta(days=120 - index * 7),
                    "updatedAt": now - timedelta(minutes=index * 3),
                    "isTestUser": True,
                    "seedTag": SEED_TAG,
                },
            )
        )
        documents.append(
            (
                "usernames",
                user["username"],
                {
                    "uid": uid,
                    "createdAt": now - timedelta(days=120 - index * 7),
                    "isTestData": True,
                    "seedTag": SEED_TAG,
                },
            )
        )

    post_times = [
        now - timedelta(minutes=22),
        now - timedelta(minutes=48),
        now - timedelta(hours=2, minutes=10),
        now - timedelta(hours=5),
        now - timedelta(days=1, hours=1),
        now - timedelta(days=1, hours=5),
        now - timedelta(days=2, hours=2),
        now - timedelta(days=3),
        now - timedelta(days=4, hours=3),
        now - timedelta(days=6),
    ]
    like_sets = [
        [1, 2, 6],
        [0, 3, 5, 8],
        [0, 4],
        [1, 4, 7],
        [0, 2, 5, 6, 7, 9],
        [1, 3],
        [2],
        [0, 3, 4, 8],
        [5, 6],
        [1, 2, 7],
    ]
    for index, text in enumerate(POSTS):
        user = USERS[index]
        post_id = f"demo_cheonan_post_{index + 1:02d}"
        documents.append(
            (
                "posts",
                post_id,
                {
                    "uid": user["uid"],
                    "authorName": user["displayName"],
                    "authorUsername": user["username"],
                    "authorPhotoUrl": None,
                    "courtId": court_id,
                    "courtName": court_name,
                    "location": location,
                    "text": text,
                    "media": [],
                    "likeUids": [user_ids[item] for item in like_sets[index]],
                    "commentCount": post_comment_counts[index],
                    "createdAt": post_times[index],
                    "updatedAt": post_times[index],
                    "isTestData": True,
                    "seedTag": SEED_TAG,
                },
            )
        )

    for index, (post_index, author_index, text) in enumerate(COMMENTS):
        user = USERS[author_index]
        post_id = f"demo_cheonan_post_{post_index + 1:02d}"
        created_at = post_times[post_index] + timedelta(minutes=12 + index * 2)
        documents.append(
            (
                "comments",
                f"demo_cheonan_comment_{index + 1:02d}",
                {
                    "postId": post_id,
                    "postOwnerUid": USERS[post_index]["uid"],
                    "courtId": court_id,
                    "uid": user["uid"],
                    "authorName": user["displayName"],
                    "authorPhotoUrl": None,
                    "text": text,
                    "createdAt": created_at,
                    "updatedAt": created_at,
                    "isTestData": True,
                    "seedTag": SEED_TAG,
                },
            )
        )

    meetup_specs = [
        (0, now + timedelta(days=1), 20, 0, 6, "3 vs 3 · 반코트", "누구나", [0, 2, 6]),
        (3, now + timedelta(days=2), 19, 30, 10, "5 vs 5 · 풀코트", "중급", [3, 1, 4, 8, 9]),
        (5, next_weekday_at(now, 5, 16), 16, 0, 6, "3 vs 3 · 반코트", "누구나", [5, 7, 2, 0]),
        (8, next_weekday_at(now, 6, 10, 30), 10, 30, 10, "5 vs 5 · 풀코트", "누구나", [8, 9, 1, 3, 4, 6]),
    ]
    for index, (creator, base, hour, minute, capacity, game_type, level, participants) in enumerate(
        meetup_specs
    ):
        starts_at = base.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if starts_at <= now:
            starts_at += timedelta(days=7)
        created_at = now - timedelta(hours=6 + index * 5)
        documents.append(
            (
                "meetups",
                f"demo_cheonan_meetup_{index + 1:02d}",
                {
                    "courtId": court_id,
                    "courtName": court_name,
                    "location": location,
                    "startsAt": starts_at,
                    "capacity": capacity,
                    "gameType": game_type,
                    "level": level,
                    "participantUids": [user_ids[item] for item in participants],
                    "createdBy": user_ids[creator],
                    "status": "open",
                    "createdAt": created_at,
                    "updatedAt": created_at,
                    "isTestData": True,
                    "seedTag": SEED_TAG,
                },
            )
        )

    month = month_key(now)
    week = week_key(now)
    ranking_specs = [
        ("court_play_stats", "all", ALL_MINUTES, ALL_SESSIONS),
        ("monthly_play_stats", month, MONTH_MINUTES, MONTH_SESSIONS),
        ("weekly_play_stats", week, WEEK_MINUTES, WEEK_SESSIONS),
    ]
    for collection, period, minutes_list, sessions_list in ranking_specs:
        scope_key = f"{period}_{court_id}"
        for index, user in enumerate(USERS):
            stat = {
                "uid": user["uid"],
                "displayName": user["displayName"],
                "username": user["username"],
                "photoUrl": None,
                "scopeKey": scope_key,
                "courtId": court_id,
                "courtName": court_name,
                "totalMinutes": minutes_list[index],
                "sessionCount": sessions_list[index],
                "lastSessionId": f"{SEED_TAG}_{index + 1:02d}",
                "updatedAt": now - timedelta(minutes=index * 4),
                "isTestData": True,
                "seedTag": SEED_TAG,
            }
            if collection == "monthly_play_stats":
                stat["monthKey"] = month
            if collection == "weekly_play_stats":
                stat["weekKey"] = week
            documents.append((collection, f"{scope_key}_{user['uid']}", stat))

    for user_index, user in enumerate(USERS):
        for offset in (0, 3, 8):
            checked_in_at = (now - timedelta(days=offset, minutes=user_index * 5)).replace(second=0)
            key = date_key(checked_in_at)
            documents.append(
                (
                    "checkins",
                    f"{court_id}_{user['uid']}_{key}",
                    {
                        "uid": user["uid"],
                        "displayName": user["displayName"],
                        "courtId": court_id,
                        "courtName": court_name,
                        "actualLocation": location,
                        "courtLocation": location,
                        "distanceMeters": 12 + user_index * 2,
                        "dateKey": key,
                        "monthKey": month_key(checked_in_at),
                        "checkedInAt": checked_in_at,
                        "isTestData": True,
                        "seedTag": SEED_TAG,
                    },
                )
            )

    live_specs = [
        (0, "playing", 6, 0, [2]),
        (2, "looking", 3, 3, [0, 6]),
        (6, "shooting", 2, 0, []),
        (7, "looking", 2, 2, [5]),
    ]
    for index, (user_index, activity, players, needed, arrivals) in enumerate(live_specs):
        user = USERS[user_index]
        updated_at = now - timedelta(minutes=8 + index * 6)
        documents.append(
            (
                "live_court_statuses",
                user["uid"],
                {
                    "uid": user["uid"],
                    "displayName": user["displayName"],
                    "username": user["username"],
                    "photoUrl": "",
                    "courtId": court_id,
                    "courtName": court_name,
                    "location": location,
                    "activity": activity,
                    "playerCount": players,
                    "neededPlayers": needed,
                    "distanceMeters": 8 + index * 4,
                    "arrivalUids": [user_ids[item] for item in arrivals],
                    "startedAt": updated_at - timedelta(minutes=20),
                    "updatedAt": updated_at,
                    "expiresAt": now + timedelta(minutes=90 - index * 8),
                    "isTestData": True,
                    "seedTag": SEED_TAG,
                },
            )
        )

    return court_id, documents


def apply_seed(db, documents: list[tuple[str, str, dict]]) -> None:
    batch = db.batch()
    for collection, document_id, data in documents:
        batch.set(db.collection(collection).document(document_id), data, merge=True)
    results = batch.commit()
    print(f"완료: {len(results)}개 문서를 생성 또는 갱신했습니다.")


def cleanup_seed(db) -> None:
    collections = {
        "users",
        "usernames",
        "posts",
        "comments",
        "meetups",
        "monthly_play_stats",
        "weekly_play_stats",
        "court_play_stats",
        "checkins",
        "live_court_statuses",
    }
    references = []
    for collection in sorted(collections):
        query = db.collection(collection).where(filter=FieldFilter("seedTag", "==", SEED_TAG))
        references.extend(document.reference for document in query.stream())
    for start in range(0, len(references), 450):
        batch = db.batch()
        for reference in references[start : start + 450]:
            batch.delete(reference)
        batch.commit()
    print(f"정리 완료: {len(references)}개 테스트 문서를 삭제했습니다.")


def main() -> None:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--apply", action="store_true", help="테스트 데이터를 생성 또는 갱신")
    action.add_argument("--cleanup", action="store_true", help="이 스크립트가 만든 테스트 데이터만 삭제")
    args = parser.parse_args()

    db = init_firestore()
    if args.cleanup:
        cleanup_seed(db)
        return

    court_id, documents = build_seed(db, datetime.now(SEOUL))
    counts = Counter(collection for collection, _, _ in documents)
    print(f"코트: {COURT_NAME} ({court_id})")
    print("문서:", ", ".join(f"{name} {count}" for name, count in sorted(counts.items())))
    if not args.apply:
        print("미리보기만 했습니다. 실제 반영은 --apply 옵션을 사용하세요.")
        return
    apply_seed(db, documents)


if __name__ == "__main__":
    main()

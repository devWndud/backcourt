# Backcourt Server

빽코트 관리자 웹과 앱 푸시 발송을 한 프로세스로 운영하는 FastAPI 서버입니다.
앱과 관리자 콘솔이 `notification_events`에 이벤트를 기록하면 서버가 실제
LIVE·약속·댓글·신고 문서를 다시 검증하고 대상자를 계산합니다. 검증된 건만
`notifications`에 넣어 iOS와 Android FCM 푸시로 전송합니다.

## 필요한 값

1. Firebase 콘솔의 프로젝트 설정 → 서비스 계정에서 비공개 키를 발급합니다.
2. 키 JSON은 서버에만 저장하고 저장소에는 추가하지 않습니다.
3. `.env.example`을 `.env`로 복사하고 실제 키의 절대 경로와 도메인을 입력합니다.
4. iOS는 Firebase 콘솔 Cloud Messaging에 Apple APNs 인증 키도 등록합니다.

## Docker 실행

`Backcourt-Server` 폴더에서 실행합니다.

```sh
cp .env.example .env
docker compose up -d --build
curl http://127.0.0.1:8000/health
```

- 관리자 콘솔: `http://서버:8000/`
- API 문서: `http://서버:8000/api/docs`
- 운영 시 Caddy 또는 Nginx로 HTTPS를 적용합니다.
- Firestore 감시 중복 발송을 막기 위해 컨테이너와 Uvicorn worker는 각각 1개로 둡니다.

## 앱 빌드

HTTPS 도메인을 앱에 컴파일 타임 환경값으로 전달합니다.

```sh
flutter run \
  --dart-define=BACKCOURT_API_URL=https://backcourt.example.com
```

로그인한 기기의 FCM 토큰은 `POST /api/push/devices`에 Firebase ID 토큰과 함께
등록됩니다. 로그아웃·계정 탈퇴 시 현재 기기 토큰은 자동 해제됩니다.

## 동작 확인

앱 로그인 후 API 문서에서 Firebase ID 토큰을 Bearer 인증으로 넣고
`POST /api/push/test`를 호출하면 자기 기기로 테스트 푸시를 보낼 수 있습니다.

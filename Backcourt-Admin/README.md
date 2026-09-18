# Backcourt Admin

빽코트 모바일 앱과 분리된 운영자 전용 정적 웹 콘솔입니다. Firebase 프로젝트
`backcourt-41720`의 인증 및 Firestore 데이터를 공유합니다. 코트명·중복·폐쇄
제보와 커뮤니티 게시물·댓글 신고를 한곳에서 실시간으로 처리합니다.

## 로컬 실행

```sh
python3 -m http.server 4173
```

브라우저에서 `http://localhost:4173`으로 접속합니다. `users/{uid}.role`이
`operator` 또는 `admin`인 계정만 제보를 읽고 처리할 수 있습니다.

- 코트 제보: 승인 시 코트명 또는 운영 상태 즉시 반영
- 콘텐츠 신고: 승인 시 신고된 게시물 또는 댓글 삭제
- 처리 알림: 승인·보류·반려 결과를 제보자 앱 알림으로 전송

## 배포

푸시 서버와 한 도메인에서 운영할 때는 `../Backcourt-Server`의 Docker 구성을
사용합니다. FastAPI의 `/`에서 이 관리자 콘솔을 제공하고 `/api`에서 기기 등록과
테스트 푸시 API를 제공합니다.

Firebase Hosting만 따로 사용할 수도 있습니다.

```sh
../Backcourt/tool/firebase deploy --only hosting --project backcourt-41720
```

웹의 Firebase 설정값은 공개 식별자이며, 실제 접근 권한은 Firestore 보안 규칙으로
제한됩니다.

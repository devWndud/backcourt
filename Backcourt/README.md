# 빽코트 (Backcourt, BC)

일상에서 코트로 돌아가는 사람들을 위한 앱입니다. 전국 농구 코트를 찾고, 현장에서 체크인하고, 지금 뛰는 사람들과 바로 합류합니다.

## UI 프로토타입

- 코트: 다크 지도, 전국 OSM 단계형 클러스터, 내 위치 이동, 검색·필터, 코트 저장
- 지금 코트: GPS 인증 현장 신호, 실시간 인원·코트 상태, 15분 뒤 합류, 90분 자동 만료
- 약속: 코트별 선착순 모집, 참가·취소, 내 코트 새 약속 알림
- 체크인: 100m GPS 인증, 48시간 리뷰 추가, 전체·월·주 코트 랭킹
- 피드: 최신·5km 주변·코트 피드, 사진·영상 게시물, 좋아요·댓글
- 안전: 게시물 신고·삭제, 사용자 차단, 차단 해제, 계정 탈퇴
- MY: 농구 프로필, 내 코트, 코트 패스포트, 월간 기록, 게시물 그리드
- 알림: 앱이 꺼져 있어도 오는 FCM 푸시와 앱 내 알림센터

홈 지도는 MapLibre와 OpenFreeMap을 사용합니다. 계정, 코트, 체크인, 리뷰, 랭킹, LIVE, 약속, 피드, 댓글, 내 코트, 알림, 신고 데이터는 Firebase와 연결되어 있습니다.

## 지도

지도 렌더링은 오픈소스 MapLibre, 지도 스타일·타일은 OpenFreeMap을 사용합니다. Google Cloud 결제 등록이나 API 키 없이 바로 실행할 수 있습니다.

- 다크 지도와 여의도 초기 화면
- 전국 OpenStreetMap 농구 코트 3,057개와 줌 단계별 클러스터
- 클러스터 터치 확대, 코트 마커 선택 및 GPS 내 위치 이동
- 체크인 인증 기준을 보여주는 100m 반경
- OpenStreetMap·OpenFreeMap·KOSTAT 출처 표시

공개 OpenFreeMap 서버는 개발과 초기 운영에 적합하지만 SLA가 없으므로, 트래픽이 커지면 자체 타일 서버나 유료 호스팅으로 교체할 수 있도록 스타일 URL을 분리해 두었습니다.

### 코트 데이터 갱신

전국 코트 시드는 OpenStreetMap의 `sport=basketball` 태그를 기준으로 생성합니다. 이름 없는 코트는 KOSTAT 2018 읍·면·동 경계에 좌표를 매칭해 지역명을 고정한 뒤 Firestore에 변경분만 시딩합니다.

```sh
dart run tool/import_osm_courts.dart
python3 tool/enrich_court_names.py
python3 tool/seed_firestore_courts.py --project backcourt-41720 --apply
```

OSM 실명은 우선 보존하고 자동 지역명은 운영자의 수정 요청 승인으로 교체합니다. 승인된 이름은 `nameSource: operator`로 저장하면 이후 카탈로그 재시딩에서도 보존됩니다. 운영자가 승인한 `closed`·`duplicate` 상태도 재시딩 시 덮어쓰지 않습니다.

## 실행

```sh
flutter pub get
flutter run \
  --dart-define=BACKCOURT_API_URL=https://backcourt.example.com
```

`BACKCOURT_API_URL`은 관리자 웹과 푸시 워커를 함께 실행하는
`../Backcourt-Server`의 HTTPS 주소입니다. 값이 없으면 앱 기능은 정상 동작하지만
기기 토큰 등록과 운영체제 푸시는 비활성화됩니다.

### 푸시 알림 준비

- Android: `google-services.json`과 알림 채널·권한 설정 완료
- iOS: Push Notifications entitlement와 background mode 설정 완료
- 서버: Firebase Admin 서비스 계정으로 알림 이벤트를 검증한 뒤 FCM 발송
- 배포 전 Firebase 콘솔에 iOS APNs 인증 키를 등록해야 함
- 서비스 계정 JSON은 앱이나 저장소에 넣지 않고 서버에만 보관

## 검증

```sh
flutter analyze
flutter test
xcrun simctl privacy <ios-simulator-id> grant location kr.backcourt.backcourt
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d <ios-simulator-id>
```

iOS 통합 테스트 결과는 `screenshots/`에 저장됩니다.

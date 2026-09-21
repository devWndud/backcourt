# Android release signing

빽코트의 Google Play 업로드 키는 Git에 저장하지 않습니다.

- 로컬 키: `android/upload-keystore.jks`
- 안전한 백업: `~/Documents/Backcourt-Release-Keys/upload-keystore.jks`
- 공개 인증서: `android/upload_certificate.pem`
- Keychain 서비스: `kr.backcourt.backcourt.upload-keystore`
- Keychain 계정: `backcourt`
- 키 별칭: `backcourt-upload`

릴리스 AAB는 프로젝트 루트에서 아래 명령으로 만듭니다.

```sh
./tool/build_android_release.sh
```

다른 Mac에서 빌드하려면 백업한 JKS를 `android/upload-keystore.jks`로 복원하고,
같은 비밀번호를 macOS Keychain에 아래 서비스·계정 이름으로 등록해야 합니다.
업로드 키를 분실하면 업데이트 배포가 막힐 수 있으므로 JKS 백업과 비밀번호를 함께 보관하되 서로 다른 안전한 장소에 둡니다.

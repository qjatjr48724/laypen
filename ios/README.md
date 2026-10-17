# Laypen iOS

스크린샷 공유 기반 필기 MVP 스캐폴딩.

## 구성

- `Laypen` — 메인 앱 (앨범/스크린샷 선택 + 필기)
- `LaypenShare` — Share Extension (공유 → 필기)
- `Shared` — `BackgroundSource`, `ToolSettings`, `StrokeStore`, 캔버스·툴바

## 생성 / 열기

```bash
cd ios
xcodegen generate
open Laypen.xcodeproj
```

Xcode에서 Team/서명만 맞춘 뒤 iPad 또는 시뮬레이터로 실행한다.

## App Group

`group.com.laypen.app` — 공유 이미지·현재 세션 저장용. Developer 계정에서 App Group capability를 활성화해야 실기기에서 동작한다.

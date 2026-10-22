# Laypen

아이패드에서 필기하는 앱. 스크린샷 위에 그리거나, 맥 화면을 아이패드로 가져와 그 위에 그린 선과 상자를 맥에서도 같이 본다.

로그인은 없다. 그림과 연결 정보는 각 기기에만 남고, 두 앱이 가까이에서 직접 주고받는다.

## 📸 스크린샷 필기

다른 앱 위에 항상 떠 있는 필기 창은 iPadOS에서 만들 수 없다. 스크린샷을 Laypen으로 가져와 그 위에 그린다.

1. 다른 앱에서 스크린샷을 찍는다.
2. 공유에서 **Laypen**을 고른다.
3. Apple Pencil로 필기한다.

앱을 직접 켜서 앨범의 스크린샷을 열 수도 있다. 작업은 기기에 남고, 다음에 켜면 이어서 열린다.

## 🖥️ 맥 화면 위에 필기

맥과 아이패드에서 Laypen을 켜 둔다. 같은 Wi-Fi이거나 서로 가까이 있으면 아이패드가 맥을 찾는다.

1. 아이패드에서 **맥에 연결**을 연다.
2. 목록에서 맥을 고르고, 맥 화면에 뜬 네 자리 코드를 입력한다.
3. 아이패드에 맥 화면이 보이고, 그 위에 그린 내용이 맥에도 겹쳐 보인다.

한 번 연결한 맥은 다음부터 코드 없이 다시 붙는다. 아이패드에서 맥 화면만 끄면 회색 캔버스에서 계속 그릴 수 있고, 맥 쪽 필기와 상자는 눈 버튼으로 잠깐 숨길 수 있다. 숨겨도 그림은 그대로 남는다.

맥 창의 닫기 버튼은 창만 닫는다. 앱까지 끄려면 **완전 종료**를 누른다.

## ✏️ 필기

- 검정 펜, 컬러 펜, 형광펜, 지우개. 도구마다 색과 굵기를 기억한다.
- 펜을 잠시 누르면 그 획이 직선으로 펴진다.
- 흰색 상자를 올려 두고, 옮기거나 크기를 바꿀 수 있다.
- 지우개를 한 번 더 누르면 필기만 지우고 상자는 남긴다. 휴지통은 필기와 상자를 같이 지운다. 둘 다 한 번 묻는다.
- 실행 취소와 다시 실행.
- 손가락과 Pencil을 나눠 쓸 수 있다.

맥에 연결한 화면에는 사진 고르기, 저장, 보내기가 없다. 직선으로 펴기와 상자는 그대로 있다.

## ✨ 강점과 구현

### 서버 없이 두 기기가 붙는다

중간에 서버를 두지 않는다. 같은 네트워크에 있거나 서로 가까이 있으면, 화면과 필기가 그 연결로만 오간다.

맥은 `Network` 프레임워크로 Bonjour 서비스 `_laypen-link._tcp`를 연다. 아이패드의 `NWBrowser`가 그 이름을 찾고, `NWConnection`으로 TCP를 맺는다. `includePeerToPeer`로 기기끼리도 찾을 수 있다. 메시지는 1바이트 종류, 4바이트 길이, 본문으로 나눈다. 화면 JPEG는 대기열에 최신 한 장만 남기고, 필기 메시지가 오래된 화면 뒤에 밀리지 않게 한다.

처음에는 맥이 보여 주는 네 자리 코드로 확인한다. 맥이 준 토큰은 아이패드 `UserDefaults`에 남고, 다음 hello에 그 토큰이 있으면 코드를 다시 묻지 않는다. Bonjour에 기기 번호가 없으면, 목록에 보인 맥 이름으로 같은 기록을 찾는다.

- `ios/Link/LinkMessages.swift`
- `ios/Link/LinkChannel.swift`
- `ios/Link/LinkTrustStore.swift`
- `ios/Laypen/MacLinkModel.swift`
- `ios/Mac/MacLinkHost.swift`

### 필기가 맥 조작을 가리지 않는다

맥 화면 위 필기는 투명한 `NSPanel`이다. 테두리가 없고, 클릭은 `ignoresMouseEvents`로 아래 앱에 넘어간다. 모든 Space에도 올라간다. `sharingType`을 `none`으로 두어, 화면을 찍을 때 이 창은 빠진다.

화면은 `ScreenCaptureKit`이 주 디스플레이를 약 8fps, 긴 변 1440px, JPEG로 보낸다. 캡처에서 Laypen 맥 앱을 빼 두어, 방금 그린 선이 다음 화면 이미지에 구워지지 않는다. 아이패드와 맥이 각자 같은 필기를 그린다.

- `ios/Mac/OverlayPanel.swift`
- `ios/Mac/ScreenSender.swift`

### 아이패드와 맥이 같은 자리를 가리킨다

점과 상자는 픽셀이 아니라, 화면에 맞춘 직사각형 안의 0–1 좌표다. 아이패드 창 크기가 바뀌어도 맥 전체 화면과 같은 비율 위치를 가리킨다. 굵기도 그 직사각형 높이의 비율이라, 양쪽에서 펜 굵기 느낌이 비슷하게 남는다.

직선을 보낼 때는 점을 `xs`, `ys` 두 실수 배열로 나눈다. `CGPoint`를 그대로 JSON으로 바꾸면 기기마다 형식이 달라질 수 있어, 좌표를 따로 보낸다.

맥 연결 화면의 직선은 점 목록을 직접 잇는다. 펜을 0.5초 멈추면 그 획의 시작과 끝을 잇고, 굵기를 한 번 0.82배로 줄인 다음 `replaceStroke`로 맥에 알린다. 지우개에는 이 동작을 붙이지 않는다.

- `ios/Laypen/MacLinkView.swift`
- `ios/Laypen/MacLinkModel.swift`
- `ios/Link/LinkMessages.swift`의 `LinkStrokeWire`

### 지운 자리 위에 다시 그릴 수 있다

지우개는 선을 다 그린 뒤에 한 겹으로 덮지 않는다. 획이 생긴 순서대로, 펜은 보통 합성으로, 지우개는 `destinationOut`으로 비트맵에만 그린다. 지운 뒤에 그린 선은 남고, 그 자리에도 다시 칠할 수 있다.

이 합성을 투명 창에 바로 하면 지운 자리가 구멍으로 남아, 나중에 그린 선이 그 구멍을 메우지 못한다. 화면 밖 비트맵에 먼저 그린 다음, 완성된 이미지를 창에 올린다. 흰색 상자는 그 이미지보다 먼저 그려, 지우개가 상자는 두고 선만 걷어 낸다.

아이패드의 맥 연결 화면도 같은 순서다. 상자와 떨어진 투명 이미지에 필기를 그린다.

- `ios/Mac/OverlayPanel.swift`
- `ios/Laypen/MacLinkView.swift`
- `ios/Link/LinkMessages.swift`의 `LinkInk`

### 맥 쪽 필기를 숨겨도 그림은 남는다

눈 버튼은 패널만 접는다. 아이패드가 `overlayVisible`로 0이나 1만 보내고, 맥은 패널을 `orderOut`하거나 다시 띄운다. 획과 상자는 양쪽에 그대로 있다. 아이패드에서 맥 화면 이미지만 끄면 캡처 대신 회색 캔버스가 보이고, 필기 영역에는 테두리가 남는다.

### 스크린샷 위에서는 PencilKit을 쓴다

스크린샷 위 필기는 `PKCanvasView`다. 공유 확장 `LaypenShare`가 이미지를 받아 App Group `group.com.laypen.app`으로 넘기면, 메인 앱이 그 위에 연다. 펜을 길게 눌러 직선으로 만드는 건 `PKStroke`를 다시 만드는 `StrokeStraightener`가 한다. 도구 색과 굵기는 `tool-settings.json`에 남아, 맥 연결 화면과 메인 캔버스가 같은 설정을 쓴다.

- `ios/Shared/DrawingCanvasView.swift`
- `ios/Shared/StrokeStraightener.swift`
- `ios/Shared/ToolSettingsStore.swift`
- `ios/LaypenShare/ShareViewController.swift`

## 프로젝트

| 위치 | 역할 |
| --- | --- |
| [`ios/Laypen`](ios/Laypen) | iPad 앱. iOS 17, iPad 전용 |
| [`ios/LaypenShare`](ios/LaypenShare) | 공유 확장. 스크린샷을 필기 화면으로 넘긴다 |
| [`ios/Mac`](ios/Mac) | Mac 앱 `LaypenMac`. macOS 14 |
| [`ios/Link`](ios/Link) | 근처 맥 찾기, 연결, 필기 전달 |
| [`ios/Shared`](ios/Shared) | 캔버스, 도구, 저장 |
| [`docs/`](docs) | 제안서와 범위 |

## 🛠️ 실행

```bash
cd ios
xcodegen generate
open Laypen.xcodeproj
```

Xcode에서 서명 팀을 맞춘 다음 스킴을 고른다.

- **Laypen** — iPad 또는 시뮬레이터
- **LaypenMac** — My Mac

실기기에서 공유 확장을 쓰려면 App Group `group.com.laypen.app`이 필요하다. 맥 연결에는 양쪽의 로컬 네트워크 권한과, 맥의 화면 기록 권한이 필요하다. 파일을 추가하거나 지우면 `xcodegen generate`를 다시 실행한다.

폴더와 권한은 [`ios/README.md`](ios/README.md)에 더 적어 두었다.

## 문서

- [제안서](docs/ipad_overlay_handwriting_app_proposal.md)
- [오버레이 검증](docs/overlay_feasibility_verification.md)
- [MVP 범위](docs/mvp_scope.md)

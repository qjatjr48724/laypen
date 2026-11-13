# Laypen

아이패드로 필기하는 앱.  
스크린샷 위에 그리거나, 맥 화면을 가져와 그 위에 그리고, 아이패드로 맥을 조작할 수 있다.

서버·로그인 없음. 같은 Wi-Fi이거나 가까이 있으면 두 기기가 직접 연결한다. USB는 충전만 한다.

## 기능

| 기능 | 설명 |
| --- | --- |
| 첫 화면 | 앱을 켜면 가운데에서 맥 연결·빈 화면·사진 필기를 고른다 |
| 스크린샷 필기 | 공유 → Laypen, 또는 첫 화면·메뉴에서 사진 열기 |
| 맥 화면 위 필기 | 첫 화면에서 저장 맥 / 다른 맥 연결 |
| 맥 클릭·스크롤 | 마우스 버튼, 또는 **손+펜** 모드 |
| 필기 잠깐 숨기기 | 눈 버튼 (맥·아이패드 동시) |
| 필기 일부 옮기기 | **선택** 도구 |

아래에서 각 기능을 설명하고 관련 코드를 적는다.

### 첫 화면

앱을 켜면 가운데에 선택지가 있다. 저장해 둔 맥이 있으면 그 이름(저장됨)으로 강조해 보여 주고, **다른 맥에 연결**로 목록도 연다. 저장 맥이 없으면 **맥에 연결**만 둔다. 이름 없는 중복 토큰은 정리해서 같은 맥이 두 줄로 뜨지 않게 한다. **빈 화면에서 필기**는 흰 캔버스, **사진 선택해서 필기**는 앨범 이미지 위 필기다. 공유로 연 이미지가 있으면 첫 화면을 건너뛴다. 필기 화면 메뉴의 **첫 화면**으로 돌아온다. 화면 테마는 시스템을 따르고, 우측 위에서 **시스템 / 밝게 / 어둡게**로 바꿀 수 있다.

- `ios/Laypen/HomeView.swift` — `HomeView`
- `ios/Laypen/ContentView.swift` — 홈 ↔ 캔버스 전환, `preferredColorScheme`
- `ios/Shared/AppColorTheme.swift` — `AppColorTheme`
- `ios/Link/LinkTrustStore.swift` — `savedPeers()`, `pruneOrphanTokens()`

### 스크린샷 필기

다른 앱 스크린샷을 Laypen으로 가져와 Pencil로 필기한다. 공유 시트에서 열거나, 앱에서 사진을 고른다. 작업은 기기에 남아 다음에 이어서 연다.

- `ios/LaypenShare/ShareViewController.swift` — `ShareViewController`
- `ios/Shared/ShareHandoff.swift` — `ShareHandoff`
- `ios/Shared/DrawingSessionModel.swift` — `DrawingSessionModel`
- `ios/Shared/DrawingCanvasView.swift` — `AnnotatedCanvas`, `DrawingCanvasView`
- `ios/Shared/SessionStore.swift` — `SessionStore`

### 근처 맥 찾기 · 코드 연결

아이패드가 Bonjour로 주변 맥을 찾는다. 맥에 뜬 네 자리 코드를 넣으면 연결된다. **새로고침**으로 목록을 다시 찾을 수 있고, 5초 쿨타임이 있다.

- `ios/Laypen/MacLinkView.swift` — `MacLinkView` (페어링 UI)
- `ios/Laypen/MacLinkModel.swift` — `MacLinkModel.start()`, `refreshNearby()`
- `ios/Mac/MacHostView.swift` — `MacHostView` (코드 표시)
- `ios/Mac/MacLinkHost.swift` — `MacLinkHost.start()`, `beginSession()`
- `ios/Link/LinkMessages.swift` — `LinkService`, `LinkHello`, `LinkAccept`

### 한 번 연결한 맥은 코드 없이 다시 연결

연결에 성공하면 토큰을 기기에 저장한다. 다음부터는 **저장됨**으로 코드 없이 붙는다. 맞지 않으면 **코드 입력**으로 다시 확인한다.

- `ios/Link/LinkTrustStore.swift` — `LinkTrustStore`
- `ios/Laypen/MacLinkModel.swift` — `NearbyMac`, `connect()`, `requestCodeEntry()`
- `ios/Mac/MacLinkHost.swift` — hello / accept / reject 처리

### 맥 화면을 아이패드로 보기

맥 주 화면을 캡처해 아이패드로 보낸다. H.264로 보내고, 안 되면 JPEG로 넘긴다. 필기 오버레이 창만 캡처에서 빼고, 코드 창은 아이패드에도 보인다. 화면 보호기가 끝나면 캡처를 다시 연다.

- `ios/Mac/ScreenSender.swift` — `ScreenSender.start()`, `openEncoder()`
- `ios/Link/LinkFrameDecoder.swift` — `LinkFrameDecoder`, `LinkVideoFrame`
- `ios/Link/LinkChannel.swift` — `LinkChannel` (프레임 순서 전송)
- `ios/Mac/MacLinkHost.swift` — `displayResumed()`, `startCapture()`

### 맥 화면 위에 필기·상자 겹치기

아이패드에서 그린 획과 흰색 상자가 맥 화면 위 투명 패널에 같이 보인다. 클릭은 아래 앱으로 통과한다.

- `ios/Mac/OverlayPanel.swift` — `OverlayPanel`, `OverlayCanvasView`
- `ios/Laypen/MacLinkModel.swift` — `addStroke()`, `setBoxes()`
- `ios/Link/LinkMessages.swift` — `StrokeSample`, `LinkBox`, `LinkInk`

### 아이패드로 맥 조작

마우스 버튼을 켜면 터치가 맥의 클릭·드래그·스크롤이 된다. **손+펜** 모드에서는 마우스 버튼 없이도 손가락으로 바로 조작한다. 한 손가락은 클릭·드래그, 두 손가락은 스크롤(손가락을 위로 쓸면 아래 내용이 보인다). 손쉬운 사용 권한이 필요하다. 마우스 모드에서 Pencil은 가볍게 대면 커서만, 세게 누르면 드래그.

- `ios/Laypen/MacLinkModel.swift` — `setControlsMac()`, `sendPointer()`
- `ios/Laypen/MacLinkView.swift` — `MacLinkCanvasView.trackControl()`, `updatePencilPressure()`, `routePenAndHand()`
- `ios/Mac/MacPointer.swift` — `MacPointer.apply()`, `scroll()`
- `ios/Link/LinkMessages.swift` — `PointerEvent`

### 입력 모드 (펜 / 손+펜 / 손)

- **펜** (기본) — 펜만 필기. 맥 조작은 마우스 버튼.
- **손+펜** — 펜은 필기, 손가락은 바로 맥 조작(메인 캔버스에서는 한 손가락 스크롤).
- **손** — 손으로 필기. 맥 조작은 마우스 버튼.

- `ios/Shared/ToolSettings.swift` — `DrawingInputMode`, `ToolSettings`
- `ios/Shared/FloatingToolbar.swift` — 입력 모드 버튼
- `ios/Laypen/MacLinkView.swift` — `routePenAndHand()`
- `ios/Shared/DrawingCanvasView.swift` — `ensureScrollTouchCount()`
- `ios/Shared/EdgeSnappingDraggable.swift` — 툴바만 히트, 빈 화면 터치는 캔버스로 통과. 메뉴를 열어도 위·가로로 밀리지 않게 위에서 고정

### 필기 도구

검정·컬러·형광·지우개. 색·굵기를 기억한다. 메뉴를 접어도 undo·redo는 보인다. 맥 연결 화면에는 사진 저장·보내기가 없다.

- `ios/Shared/ToolSettings.swift` — `DrawingToolKind`, `ToolSettings`
- `ios/Shared/ToolSettingsStore.swift` — `ToolSettingsStore`
- `ios/Shared/FloatingToolbar.swift` — `FloatingToolbar`

### 홀드로 직선 만들기

펜을 잠시 멈추면 그 획이 직선으로 펴진다. 맥 연결 화면에도 같다.

- `ios/Shared/StrokeStraightener.swift` — `StrokeStraightener`
- `ios/Shared/DrawingCanvasView.swift` — Coordinator 홀드 스냅
- `ios/Laypen/MacLinkModel.swift` — `straightenLastStroke()`
- `ios/Laypen/MacLinkView.swift` — `snapStraight()`

### 필기 일부 선택·이동

선택 도구로 영역을 잡아 획을 옮긴다. 맥 오버레이에도 같이 반영된다.

- `ios/Shared/ToolSettings.swift` — `DrawingToolKind.selection`
- `ios/Laypen/MacLinkView.swift` — `beginInkSelection()`, `finishInkSelection()`, `clearInkSelection()`
- `ios/Laypen/MacLinkModel.swift` — `replaceInk()`
- `ios/Mac/OverlayPanel.swift` — `replaceInk()`
- `ios/Link/LinkMessages.swift` — `LinkMessageKind.replaceInk`, `LinkStroke.intersects()`

### 흰색 상자

가림용 상자를 올리고, 옮기거나 크기를 바꾼다. 지우개는 상자는 두고 필기만 지운다.

- `ios/Shared/WhiteRectShape.swift` — `WhiteRectShape`
- `ios/Shared/WhiteboardLayer.swift` — `WhiteboardLayer`
- `ios/Laypen/MacLinkView.swift` — 상자 배치·편집
- `ios/Link/LinkMessages.swift` — `LinkBox`

### 지우개 · 전체 삭제

지우개를 한 번 더 누르면 필기만 지운다. 휴지통은 필기+상자를 지운다. 둘 다 확인 후 실행한다. 지운 자리 위에도 다시 그릴 수 있다.

- `ios/Link/LinkMessages.swift` — `LinkInk`
- `ios/Mac/OverlayPanel.swift` — `OverlayCanvasView` (`destinationOut` 오프스크린)
- `ios/Laypen/MacLinkModel.swift` — `clearInk()`, `clearAll()`
- `ios/Shared/FloatingToolbar.swift` — 지우개·휴지통 버튼

### 필기 숨기기 · 맥 화면 끄기

눈 버튼은 필기·상자를 맥과 아이패드에서 같이 가린다. 데이터는 남는다. 맥 화면 끄면 회색 캔버스에서 계속 그린다.

- `ios/Laypen/MacLinkModel.swift` — `showsMacInk`, `showsMacScreen`, `sendInkVisibility()`
- `ios/Mac/OverlayPanel.swift` — `setContentVisible()`
- `ios/Laypen/MacLinkView.swift` — `MacLinkCanvasView.draw`
- `ios/Shared/FloatingToolbar.swift` — 눈·맥 화면 버튼

### 연결 안내 배너

연결 직후 현재 입력 모드 안내를 상단에 3초간 한 번만 보여 주고, 서서히 사라진다.

- `ios/Laypen/MacLinkView.swift` — `showConnectBannerOnce()`

### 좌표를 양쪽에 같게 맞추기

점·상자는 화면 fit 영역 기준 0–1 좌표다. 직선은 `xs`/`ys` 배열로 보내 기기 간 JSON 차이를 피한다.

- `ios/Link/LinkMessages.swift` — `LinkStrokeWire`, `LinkStrokeStyle`
- `ios/Laypen/MacLinkView.swift` — `normalize`, `map`
- `ios/Mac/OverlayPanel.swift` — `map`

### 서버 없는 근거리 전송

Bonjour `_laypen-link._tcp` + TCP. 메시지 종류 1바이트 + 길이 4바이트 + 본문. 화면 프레임은 순서를 지키고, 필기·포인터가 앞에 나간다.

- `ios/Link/LinkMessages.swift` — `LinkService`, `LinkCodec`, `LinkFramer`
- `ios/Link/LinkChannel.swift` — `LinkChannel`

---

## 프로젝트

| 위치 | 역할 |
| --- | --- |
| [`ios/Laypen`](ios/Laypen) | iPad 앱. iOS 17, iPad 전용 |
| [`ios/LaypenShare`](ios/LaypenShare) | 공유 확장 |
| [`ios/Mac`](ios/Mac) | Mac 앱 `LaypenMac`. macOS 14 |
| [`ios/Link`](ios/Link) | 연결, 화면·필기·포인터 프로토콜 |
| [`ios/Shared`](ios/Shared) | 캔버스, 도구, 저장 |
| [`docs/`](docs) | 제안서·검증·범위 |

## 실행

```bash
cd ios
xcodegen generate
open Laypen.xcodeproj
```

- **Laypen** — iPad / 시뮬레이터  
- **LaypenMac** — My Mac  

필요 권한: App Group `group.com.laypen.app`, 로컬 네트워크, 맥 화면 기록·손쉬운 사용.  
파일을 추가·삭제하면 `xcodegen generate`를 다시 실행한다.  
자세한 폴더·권한은 [`ios/README.md`](ios/README.md).

## 문서

- [제안서](docs/ipad_overlay_handwriting_app_proposal.md)
- [오버레이 검증](docs/overlay_feasibility_verification.md)
- [MVP 범위](docs/mvp_scope.md)

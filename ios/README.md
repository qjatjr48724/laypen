# Laypen 앱

아이패드 필기 앱과, 그 필기를 맥 화면 위에 겹쳐 보여주는 맥 앱. 프로젝트는 XcodeGen으로 만든다.

## 타깃

| 스킴 | 플랫폼 | 하는 일 |
| --- | --- | --- |
| `Laypen` | iOS 17, iPad | 스크린샷 필기, 맥 연결 |
| `LaypenShare` | iOS 17 | 공유 시트에서 이미지를 받아 필기 화면으로 넘긴다. `Laypen`에 포함되어 빌드된다 |
| `LaypenMac` | macOS 14 | 화면을 아이패드로 보내고, 받은 필기와 상자를 화면 위에 그린다 |

## 폴더

```text
Laypen/          메인 앱
LaypenShare/     공유 확장
Mac/             맥 앱, 오버레이, 화면 캡처
Link/            연결 프로토콜과 신뢰 저장
Shared/          캔버스, 도구, 세션 저장
project.yml      XcodeGen 설정. 프로젝트 파일은 여기서 다시 만든다
```

`Laypen`과 `LaypenMac`은 `Link`를 함께 빌드한다. `Shared`는 아이패드 앱과 공유 확장만 쓴다.

## 열기

```bash
cd ios
xcodegen generate
open Laypen.xcodeproj
```

Xcode에서 Team과 서명을 맞춘다. Swift 파일을 추가하거나 지우면 `xcodegen generate`를 다시 실행한다. `project.pbxproj`는 직접 고치지 않는다.

`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`는 `false`로 둔다. 맥 화면 위 필기는 `LaypenMac`이 담당한다.

## 권한

- App Group `group.com.laypen.app` — 공유 이미지와 현재 세션. 실기기에서는 Developer 계정의 App Group이 켜져 있어야 한다.
- 로컬 네트워크, Bonjour `_laypen-link._tcp` — 아이패드와 맥이 서로를 찾고 필기를 주고받는다.
- 화면 기록 — 맥이 주 디스플레이를 아이패드로 보낸다. 디버거로 실행하면 권한 창에 Xcode 이름이 뜰 수 있다. 허용한 뒤 연결을 다시 하면 화면이 넘어온다.

## 맥 연결

1. 스킴 `LaypenMac`으로 맥 앱을 실행하고, 스킴 `Laypen`으로 아이패드 앱을 실행한다.
2. 아이패드의 **맥에 연결**에서 맥을 고르고, 맥에 표시된 네 자리 코드를 입력한다.
3. 연결에 성공하면 그 맥은 기기에 저장된다. 다음 연결부터는 코드 칸이 없고 **저장됨**이 보인다.

코드를 연결하는 동안에는 **코드 새로 만들기**를 누르지 않는다. 맥을 완전히 끄려면 창 닫기가 아니라 **완전 종료**를 누른다. 앱을 지우고 다시 설치하면 저장된 연결도 사라진다.

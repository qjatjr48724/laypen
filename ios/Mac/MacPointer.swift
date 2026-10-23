import AppKit
import ApplicationServices
import CoreGraphics

enum MacPointer {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    static func apply(_ event: PointerEvent) {
        guard isTrusted, let screen = NSScreen.main else { return }
        let point = quartzPoint(x: event.x, y: event.y, on: screen)
        switch event.phase {
        case PointerEvent.began:
            post(type: .leftMouseDown, at: point)
        case PointerEvent.moved:
            post(type: .leftMouseDragged, at: point)
        case PointerEvent.hover:
            post(type: .mouseMoved, at: point)
        case PointerEvent.ended, PointerEvent.cancelled:
            post(type: .leftMouseUp, at: point)
        case PointerEvent.scroll:
            scroll(dx: event.dx, dy: event.dy, at: point, on: screen)
        default:
            break
        }
    }

    /// 화면 비율 좌표(왼쪽 위가 0)를 CGEvent가 쓰는 전역 좌표로 바꾼다.
    private static func quartzPoint(x: Float, y: Float, on screen: NSScreen) -> CGPoint {
        let unitX = min(1, max(0, CGFloat(x)))
        let unitY = min(1, max(0, CGFloat(y)))
        let frame = screen.frame
        let appKit = CGPoint(
            x: frame.minX + unitX * frame.width,
            y: frame.maxY - unitY * frame.height
        )
        let primaryHeight = NSScreen.screens.map(\.frame.maxY).max() ?? frame.maxY
        return CGPoint(x: appKit.x, y: primaryHeight - appKit.y)
    }

    private static func post(type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private static func scroll(dx: Float, dy: Float, at point: CGPoint, on screen: NSScreen) {
        let frame = screen.frame
        let wheelX = Int32((CGFloat(dx) * frame.width).rounded())
        let wheelY = Int32((-CGFloat(dy) * frame.height).rounded())
        guard wheelX != 0 || wheelY != 0 else { return }
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: wheelY,
            wheel2: wheelX,
            wheel3: 0
        ) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    /// 연결이 끊길 때 눌린 채로 남은 마우스 버튼을 놓는다.
    static func releaseButton() {
        guard isTrusted, let point = CGEvent(source: nil)?.location else { return }
        post(type: .leftMouseUp, at: point)
    }
}

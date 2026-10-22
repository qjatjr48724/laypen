import AppKit
import SwiftUI

struct MacHostView: View {
    @ObservedObject var host: MacLinkHost

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("아이패드에서 이 코드를 입력")
                .font(.headline)
            Text(host.code)
                .font(.system(size: 64, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity)
            Text(host.status)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("아이패드 Laypen의 맥에 연결에서 주변 맥을 고르고 코드를 입력합니다. 필기는 이 맥 화면 위에 겹쳐 보입니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let captureWarning = host.captureWarning {
                Text(captureWarning)
                    .font(.callout)
                    .foregroundStyle(.orange)
                Button("화면 기록 설정 열기", action: host.openCaptureSettings)
            }
            HStack {
                Button("코드 새로 만들기", action: host.regenerateCode)
                    .disabled(host.isConnected)
                Button("획 지우기", action: host.clearStrokes)
            }
            Spacer(minLength: 0)
            Button("완전 종료", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 360)
        .onAppear { host.start() }
    }
}

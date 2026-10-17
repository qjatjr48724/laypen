import SwiftUI

/// 스크린샷 → Laypen 진입을 줄이는 iOS 단축어 자동화 안내.
/// OS가 자동화를 앱이 대신 등록하는 것은 허용하지 않으므로, 단계 안내 + 단축어 앱 열기만 제공한다.
struct ShortcutsGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("스크린샷을 찍으면 Laypen을 바로 열도록, iPad의 단축어 자동화를 직접 추가할 수 있습니다. 앱이 대신 등록해 줄 수는 없습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        step(1, title: "단축어 앱 열기", detail: "아래 버튼으로 단축어 앱을 연 뒤, 아래쪽 「자동화」 탭을 선택합니다.")
                        step(2, title: "개인 자동화 만들기", detail: "「+」 → 「개인 자동화 만들기」 → 「스크린샷」을 선택합니다.")
                        step(3, title: "앱 열기 추가", detail: "동작에서 「앱 열기」를 추가하고 Laypen을 고릅니다.")
                        step(4, title: "바로 실행(선택)", detail: "「실행 전에 묻기」를 끄면 캡처 후 확인 없이 Laypen이 열립니다.")
                    }

                    Text("이미지는 자동으로 들어오지 않습니다. Laypen이 열린 뒤 메뉴의 「스크린샷 선택」으로 방금 찍은 화면을 고르면 됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openShortcutsApp()
                    } label: {
                        Label("단축어 앱 열기", systemImage: "arrow.up.forward.app")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .navigationTitle("단축어로 빠르게 열기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openShortcutsApp() {
        guard let url = URL(string: "shortcuts://") else { return }
        openURL(url)
    }
}

#Preview {
    ShortcutsGuideSheet()
}

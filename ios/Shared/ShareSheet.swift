import SwiftUI
import UIKit

/// 시스템 공유 시트. SwiftUI sheet의 detent로 세로 길이를 조절한다.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks
        ]
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension View {
    /// 내보내기용 공유 시트 — 기본을 중간 높이로 두고, 필요하면 늘릴 수 있게 한다.
    func laypenShareSheet(
        image: Binding<UIImage?>,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        sheet(
            isPresented: Binding(
                get: { image.wrappedValue != nil },
                set: { if !$0 { image.wrappedValue = nil; onDismiss?() } }
            )
        ) {
            if let shareImage = image.wrappedValue {
                ShareSheet(items: [shareImage]) {
                    image.wrappedValue = nil
                    onDismiss?()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
            }
        }
    }
}

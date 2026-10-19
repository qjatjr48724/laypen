import SwiftUI

/// 좌/우 가장자리에 붙인 채 Y만 이동.
/// 가로 위치는 바깥쪽 변 기준이라 메뉴가 커져도 접기/ON 버튼이 옆으로 밀리지 않는다.
struct EdgeSnappingDraggable<Content: View>: View {
    @ViewBuilder var content: (_ maxHeight: CGFloat) -> Content

    @State private var dockedLeading = false
    @State private var y: CGFloat?
    @State private var dragStartY: CGFloat?
    @State private var contentSize: CGSize = CGSize(width: 100, height: 48)

    private let margin: CGFloat = 12
    /// Split View / Slide Over 하단 그립과 겹치지 않게
    private let bottomGrabberInset: CGFloat = 28
    private let edgeAnimation = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.1)

    var body: some View {
        GeometryReader { geo in
            let usable = usableRect(in: geo)
            let resolvedY = clampedY(y ?? usable.minY + 48, usable: usable)
            // 중심점으로 두되, trailing이면 오른쪽 변이 usable.maxX에 붙도록 계산
            let anchorX = dockedLeading
                ? usable.minX + contentSize.width / 2
                : usable.maxX - contentSize.width / 2
            let anchorY = resolvedY + contentSize.height / 2

            content(usable.height)
                .fixedSize()
                .overlay {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                contentSize = proxy.size
                                y = clampedY(y ?? resolvedY, usable: usable)
                            }
                            .onChange(of: proxy.size) { _, newSize in
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    contentSize = newSize
                                    y = clampedY(y ?? resolvedY, usable: usable)
                                }
                            }
                            .onChange(of: usable) { _, newUsable in
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    y = clampedY(y ?? resolvedY, usable: newUsable)
                                }
                            }
                    }
                }
                .position(x: anchorX, y: anchorY)
                // 메뉴 크기 변화로 버튼이 미끄러지는 애니메이션만 제거
                .animation(nil, value: contentSize)
                .animation(nil, value: resolvedY)
                .animation(edgeAnimation, value: dockedLeading)
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named("edgeDock"))
                        .onChanged { value in
                            if dragStartY == nil {
                                dragStartY = resolvedY
                            }
                            guard let startY = dragStartY else { return }

                            let preferLeading = value.location.x < geo.size.width / 2
                            if preferLeading != dockedLeading {
                                withAnimation(edgeAnimation) {
                                    dockedLeading = preferLeading
                                }
                            }

                            y = clampedY(startY + value.translation.height, usable: usable)
                        }
                        .onEnded { value in
                            dragStartY = nil
                            let preferLeading = value.location.x < geo.size.width / 2
                            withAnimation(edgeAnimation) {
                                dockedLeading = preferLeading
                            }
                            y = clampedY(y ?? resolvedY, usable: usable)
                        }
                )
        }
        // ignoresSafeArea를 쓰면 inset이 0이 되어 상태바(시계~배터리)와 겹친다.
        .coordinateSpace(name: "edgeDock")
        .allowsHitTesting(true)
    }

    /// safe area 레이아웃 + margin 안쪽만 사용 (상단 상태바 아래, 하단 멀티태스킹 그립 위).
    private func usableRect(in geo: GeometryProxy) -> CGRect {
        let safe = geo.safeAreaInsets
        let minX = safe.leading + margin
        let minY = safe.top + margin
        let maxX = geo.size.width - safe.trailing - margin
        let maxY = geo.size.height - safe.bottom - margin - bottomGrabberInset
        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    private func clampedY(_ value: CGFloat, usable: CGRect) -> CGFloat {
        let height = min(contentSize.height, usable.height)
        let maxY = usable.maxY - height
        return min(max(value, usable.minY), max(usable.minY, maxY))
    }
}

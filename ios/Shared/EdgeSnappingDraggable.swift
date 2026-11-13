import SwiftUI

/// 좌/우 가장자리에 붙인 채 Y만 이동.
/// 가로 위치는 바깥쪽 변 기준이라 메뉴가 커져도 접기/ON 버튼이 옆으로 밀리지 않는다.
/// 메뉴가 커져도 위·가로로 밀리지 않게, 위에서부터 배치하고 남는 아래만 비운다.
struct EdgeSnappingDraggable<Content: View>: View {
    @ViewBuilder var content: (_ maxHeight: CGFloat) -> Content

    @State private var dockedLeading = false
    @State private var y: CGFloat?
    @State private var dragStartY: CGFloat?
    @State private var contentSize: CGSize = CGSize(width: 100, height: 48)
    @State private var containerSize: CGSize = .zero
    @State private var safeInsets = EdgeInsets()

    private let margin: CGFloat = 12
    /// Split View / Slide Over 하단 그립과 겹치지 않게
    private let bottomGrabberInset: CGFloat = 28
    private let edgeAnimation = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.1)

    var body: some View {
        let usable = usableRect()
        let resolvedY = clampedY(y ?? usable.minY + 48, usable: usable)
        let topPad = max(0, resolvedY)

        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        containerSize = geo.size
                        safeInsets = geo.safeAreaInsets
                        y = clampedY(y ?? usable.minY + 48, usable: usableRect())
                    }
                    .onChange(of: geo.size) { _, newSize in
                        containerSize = newSize
                        reclampY()
                    }
                    .onChange(of: geo.safeAreaInsets) { _, newInsets in
                        safeInsets = newInsets
                        reclampY()
                    }
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topPad)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    if dockedLeading {
                        Color.clear
                            .frame(width: usable.minX)
                            .allowsHitTesting(false)
                        toolbar(usableHeight: usable.height, resolvedY: resolvedY)
                        Spacer(minLength: 0)
                            .allowsHitTesting(false)
                    } else {
                        Spacer(minLength: 0)
                            .allowsHitTesting(false)
                        toolbar(usableHeight: usable.height, resolvedY: resolvedY)
                        Color.clear
                            .frame(width: max(0, containerSize.width - usable.maxX))
                            .allowsHitTesting(false)
                    }
                }
                .animation(edgeAnimation, value: dockedLeading)
                .animation(nil, value: contentSize)

                // 고정 높이 bottomPad 대신 유동 Spacer — 메뉴가 커져도 전체를 가운데로 밀어 올리지 않는다.
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "edgeDock")
    }

    @ViewBuilder
    private func toolbar(usableHeight: CGFloat, resolvedY: CGFloat) -> some View {
        content(max(80, usableHeight))
            .fixedSize()
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                contentSize = newSize
                                // 높이만 커질 때는 가능하면 위(y)를 유지하고, 아래로 넘칠 때만 올린다.
                                reclampY()
                            }
                        }
                }
                .allowsHitTesting(false)
            }
            .animation(nil, value: contentSize)
            .animation(nil, value: resolvedY)
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("edgeDock"))
                    .onChanged { value in
                        if dragStartY == nil {
                            dragStartY = resolvedY
                        }
                        guard let startY = dragStartY else { return }

                        let preferLeading = value.location.x < containerSize.width / 2
                        if preferLeading != dockedLeading {
                            withAnimation(edgeAnimation) {
                                dockedLeading = preferLeading
                            }
                        }

                        y = clampedY(startY + value.translation.height, usable: usableRect())
                    }
                    .onEnded { value in
                        dragStartY = nil
                        let preferLeading = value.location.x < containerSize.width / 2
                        withAnimation(edgeAnimation) {
                            dockedLeading = preferLeading
                        }
                        y = clampedY(y ?? resolvedY, usable: usableRect())
                    }
            )
    }

    private func reclampY() {
        guard let current = y else { return }
        y = clampedY(current, usable: usableRect())
    }

    /// safe area 레이아웃 + margin 안쪽만 사용 (상단 상태바 아래, 하단 멀티태스킹 그립 위).
    private func usableRect() -> CGRect {
        let minX = safeInsets.leading + margin
        let minY = safeInsets.top + margin
        let maxX = containerSize.width - safeInsets.trailing - margin
        let maxY = containerSize.height - safeInsets.bottom - margin - bottomGrabberInset
        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    /// 위쪽 y를 유지하되, 아래를 벗어나면 그때만 올린다. 화면 밖(위)으로는 나가지 않는다.
    private func clampedY(_ value: CGFloat, usable: CGRect) -> CGFloat {
        let height = min(max(contentSize.height, 1), max(usable.height, 1))
        let maxY = max(usable.minY, usable.maxY - height)
        return min(max(value, usable.minY), maxY)
    }
}

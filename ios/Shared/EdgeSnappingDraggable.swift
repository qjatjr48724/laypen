import SwiftUI

/// 좌/우 가장자리에 붙인 채 Y만 이동. 뷰의 **왼쪽 위** 기준으로 두어 화면 밖으로 나가지 않는다.
struct EdgeSnappingDraggable<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @State private var dockedLeading = false
    @State private var y: CGFloat?
    @State private var dragStartY: CGFloat?
    @State private var contentSize: CGSize = CGSize(width: 100, height: 48)

    private let margin: CGFloat = 12
    private let animation = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.1)

    var body: some View {
        GeometryReader { geo in
            let usable = usableRect(in: geo)
            let x = dockedX(leading: dockedLeading, usable: usable)
            let resolvedY = clampedY(y ?? usable.minY + 48, usable: usable)

            content()
                .fixedSize()
                .overlay {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { contentSize = proxy.size }
                            .onChange(of: proxy.size) { _, newSize in
                                contentSize = newSize
                                y = clampedY(resolvedY, usable: usable)
                            }
                    }
                }
                .offset(x: x, y: resolvedY)
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named("edgeDock"))
                        .onChanged { value in
                            if dragStartY == nil {
                                dragStartY = resolvedY
                            }
                            guard let startY = dragStartY else { return }

                            let preferLeading = value.location.x < geo.size.width / 2
                            if preferLeading != dockedLeading {
                                withAnimation(animation) {
                                    dockedLeading = preferLeading
                                }
                            }

                            y = clampedY(startY + value.translation.height, usable: usable)
                        }
                        .onEnded { value in
                            dragStartY = nil
                            let preferLeading = value.location.x < geo.size.width / 2
                            withAnimation(animation) {
                                dockedLeading = preferLeading
                                y = clampedY(y ?? resolvedY, usable: usable)
                            }
                        }
                )
        }
        // ignoresSafeArea를 쓰면 inset이 0이 되어 상태바(시계~배터리)와 겹친다.
        .coordinateSpace(name: "edgeDock")
    }

    /// safe area 레이아웃 + margin 안쪽만 사용 (상단 상태바 아래).
    private func usableRect(in geo: GeometryProxy) -> CGRect {
        let safe = geo.safeAreaInsets
        let minX = safe.leading + margin
        let minY = safe.top + margin
        let maxX = geo.size.width - safe.trailing - margin
        let maxY = geo.size.height - safe.bottom - margin
        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    private func dockedX(leading: Bool, usable: CGRect) -> CGFloat {
        if leading {
            return usable.minX
        }
        return usable.maxX - contentSize.width
    }

    private func clampedY(_ value: CGFloat, usable: CGRect) -> CGFloat {
        let maxY = max(usable.minY, usable.maxY - contentSize.height)
        return min(max(value, usable.minY), maxY)
    }
}

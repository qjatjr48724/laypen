import SwiftUI

struct WhiteboardLayer: View {
    @Binding var shapes: [WhiteRectShape]
    @Binding var selectedID: UUID?
    var isDrawingEnabled: Bool
    var isPlacing: Bool
    var onPlacementFinished: () -> Void
    var onShapesChanged: () -> Void

    @State private var placeStart: CGPoint?
    @State private var placeCurrent: CGPoint?
    @State private var moveStartRect: CGRect?
    @State private var resizeStartRect: CGRect?
    @State private var showTrash = false
    @State private var overTrash = false
    @State private var canvasSize: CGSize = .zero

    private let handleSize: CGFloat = 16
    private let minSide: CGFloat = 40
    private let trashSize = CGSize(width: 72, height: 40)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                ForEach(shapes) { shape in
                    shapeView(shape, canvasSize: size)
                }

                if let start = placeStart, let current = placeCurrent, isPlacing {
                    let draft = CGRect(
                        x: start.x,
                        y: start.y,
                        width: current.x - start.x,
                        height: current.y - start.y
                    ).standardized
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.5)
                        )
                        .frame(width: max(1, draft.width), height: max(1, draft.height))
                        .position(x: draft.midX, y: draft.midY)
                        .allowsHitTesting(false)
                }

                if showTrash {
                    trashBin
                        .frame(width: trashSize.width, height: trashSize.height)
                        .position(x: size.width / 2, y: size.height - 52)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "whiteboard")
            .onAppear { canvasSize = size }
            .onChange(of: size) { _, newSize in canvasSize = newSize }
            // contentShape를 제스처보다 먼저 적용해야 빈 화면 드래그(상자 배치)가 동작한다.
            .modifier(FullCanvasHitShape(enabled: isPlacing))
            .gesture(placementGesture, including: isPlacing ? .gesture : .subviews)
            // 배치 중엔 전체 히트, 편집 중엔 상자만 히트 → 빈 곳은 핀치/팬으로 전달
            .allowsHitTesting(isPlacing || (!isDrawingEnabled && !shapes.isEmpty))
        }
    }

    private func trashHitFrame(in size: CGSize) -> CGRect {
        let center = CGPoint(x: size.width / 2, y: size.height - 52)
        return CGRect(
            x: center.x - trashSize.width / 2,
            y: center.y - trashSize.height / 2,
            width: trashSize.width,
            height: trashSize.height
        )
    }

    private var trashBin: some View {
        VStack(spacing: 2) {
            Image(systemName: overTrash ? "trash.fill" : "trash")
                .font(.body.weight(.semibold))
            Text("삭제")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(overTrash ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(overTrash ? Color.red : Color(.secondarySystemBackground).opacity(0.96))
        )
        .shadow(radius: 4, y: 1)
        .scaleEffect(overTrash ? 1.08 : 1)
        .animation(.easeOut(duration: 0.15), value: overTrash)
    }

    @ViewBuilder
    private func shapeView(_ shape: WhiteRectShape, canvasSize: CGSize) -> some View {
        let selected = selectedID == shape.id && !isDrawingEnabled && !isPlacing

        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.14), radius: 2, y: 1)

            if selected {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)

                ForEach(Corner.allCases) { corner in
                    resizeHandle(corner, shape: shape)
                }
            }
        }
        .frame(width: shape.width, height: shape.height)
        .position(x: shape.rect.midX, y: shape.rect.midY)
        .onTapGesture {
            guard !isDrawingEnabled, !isPlacing else { return }
            selectedID = shape.id
        }
        .gesture(moveGesture(for: shape, canvasSize: canvasSize), including: (!isDrawingEnabled && !isPlacing) ? .gesture : .subviews)
    }

    private enum Corner: String, CaseIterable, Identifiable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        var id: String { rawValue }
    }

    private func resizeHandle(_ corner: Corner, shape: WhiteRectShape) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .frame(width: handleSize, height: handleSize)
            .offset(handleOffset(corner, shape: shape))
            .highPriorityGesture(
                DragGesture()
                    .onChanged { value in
                        guard let index = shapes.firstIndex(where: { $0.id == shape.id }) else { return }
                        selectedID = shape.id
                        if resizeStartRect == nil {
                            resizeStartRect = shapes[index].rect
                        }
                        guard let start = resizeStartRect else { return }
                        shapes[index].rect = resized(start, corner: corner, translation: value.translation)
                    }
                    .onEnded { _ in
                        resizeStartRect = nil
                        onShapesChanged()
                    }
            )
    }

    private func handleOffset(_ corner: Corner, shape: WhiteRectShape) -> CGSize {
        switch corner {
        case .topLeading: return CGSize(width: -shape.width / 2, height: -shape.height / 2)
        case .topTrailing: return CGSize(width: shape.width / 2, height: -shape.height / 2)
        case .bottomLeading: return CGSize(width: -shape.width / 2, height: shape.height / 2)
        case .bottomTrailing: return CGSize(width: shape.width / 2, height: shape.height / 2)
        }
    }

    private func resized(_ original: CGRect, corner: Corner, translation: CGSize) -> CGRect {
        var rect = original
        switch corner {
        case .topLeading:
            let maxX = original.maxX
            let maxY = original.maxY
            rect.origin.x = min(maxX - minSide, original.minX + translation.width)
            rect.origin.y = min(maxY - minSide, original.minY + translation.height)
            rect.size.width = max(minSide, maxX - rect.origin.x)
            rect.size.height = max(minSide, maxY - rect.origin.y)
        case .topTrailing:
            rect.origin.y = min(original.maxY - minSide, original.minY + translation.height)
            rect.size.width = max(minSide, original.width + translation.width)
            rect.size.height = max(minSide, original.maxY - rect.origin.y)
        case .bottomLeading:
            rect.origin.x = min(original.maxX - minSide, original.minX + translation.width)
            rect.size.width = max(minSide, original.maxX - rect.origin.x)
            rect.size.height = max(minSide, original.height + translation.height)
        case .bottomTrailing:
            rect.size.width = max(minSide, original.width + translation.width)
            rect.size.height = max(minSide, original.height + translation.height)
        }
        return rect
    }

    private func moveGesture(for shape: WhiteRectShape, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("whiteboard"))
            .onChanged { value in
                guard let index = shapes.firstIndex(where: { $0.id == shape.id }) else { return }
                if moveStartRect == nil {
                    moveStartRect = shapes[index].rect
                    selectedID = shape.id
                    showTrash = true
                }
                guard let start = moveStartRect else { return }
                var next = start
                next.origin.x = start.minX + value.translation.width
                next.origin.y = start.minY + value.translation.height
                shapes[index].rect = next

                // 손가락(펜) 위치가 휴지통 영역 안인지 판정
                overTrash = trashHitFrame(in: canvasSize).contains(value.location)
            }
            .onEnded { value in
                defer {
                    moveStartRect = nil
                    showTrash = false
                    overTrash = false
                }
                guard let index = shapes.firstIndex(where: { $0.id == shape.id }) else { return }
                let fingerInTrash = trashHitFrame(in: canvasSize).contains(value.location)
                if fingerInTrash {
                    let id = shapes[index].id
                    shapes.remove(at: index)
                    if selectedID == id { selectedID = nil }
                }
                onShapesChanged()
            }
    }

    private var placementGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isPlacing else { return }
                if placeStart == nil {
                    placeStart = value.startLocation
                }
                placeCurrent = value.location
            }
            .onEnded { value in
                defer {
                    placeStart = nil
                    placeCurrent = nil
                    onPlacementFinished()
                }
                guard isPlacing, let start = placeStart else { return }
                let draft = CGRect(
                    x: start.x,
                    y: start.y,
                    width: value.location.x - start.x,
                    height: value.location.y - start.y
                )
                let standardized = draft.standardized
                guard standardized.width >= 24, standardized.height >= 24 else { return }
                let shape = WhiteRectShape.make(from: standardized)
                shapes.append(shape)
                selectedID = shape.id
                onShapesChanged()
            }
    }
}

/// 배치 모드에서만 캔버스 전체 히트 영역을 연다.
private struct FullCanvasHitShape: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.contentShape(Rectangle())
        } else {
            content
        }
    }
}

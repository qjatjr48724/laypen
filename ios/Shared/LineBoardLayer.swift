import SwiftUI

struct LineBoardLayer: View {
    @Binding var lines: [LineShape]
    @Binding var selectedID: UUID?
    var isDrawingEnabled: Bool
    var isPlacing: Bool
    var draftColorHex: String
    var draftWidth: CGFloat
    var onPlacementFinished: () -> Void
    var onLinesChanged: () -> Void

    @State private var placeStart: CGPoint?
    @State private var placeCurrent: CGPoint?
    @State private var moveStartLine: LineShape?
    @State private var showTrash = false
    @State private var overTrash = false
    @State private var canvasSize: CGSize = .zero

    private let handleSize: CGFloat = 16
    private let hitSlop: CGFloat = 14
    private let trashSize = CGSize(width: 72, height: 40)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                ForEach(lines) { line in
                    lineView(line, canvasSize: size)
                }

                if let start = placeStart, let current = placeCurrent, isPlacing {
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: current)
                    }
                    .stroke(
                        Color(hex: draftColorHex),
                        style: StrokeStyle(lineWidth: draftWidth, lineCap: .round)
                    )
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
            .coordinateSpace(name: "lineboard")
            .onAppear { canvasSize = size }
            .onChange(of: size) { _, newSize in canvasSize = newSize }
            .gesture(placementGesture, including: isPlacing ? .gesture : .subviews)
            // 빈 영역은 통과시키고, 선/배치 제스처만 받는다.
            .allowsHitTesting(isPlacing || (!isDrawingEnabled && !lines.isEmpty))
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
    private func lineView(_ line: LineShape, canvasSize: CGSize) -> some View {
        let selected = selectedID == line.id && !isDrawingEnabled && !isPlacing

        ZStack {
            Path { path in
                path.move(to: line.start)
                path.addLine(to: line.end)
            }
            .stroke(
                Color(hex: line.colorHex),
                style: StrokeStyle(lineWidth: line.width, lineCap: .round)
            )

            // 히트 영역을 넓히기 위한 투명 스트로크
            Path { path in
                path.move(to: line.start)
                path.addLine(to: line.end)
            }
            .stroke(Color.clear, style: StrokeStyle(lineWidth: max(line.width, hitSlop * 2), lineCap: .round))

            if selected {
                endpointHandle(at: line.start) {
                    DragGesture(coordinateSpace: .named("lineboard"))
                        .onChanged { value in
                            guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
                            lines[index].start = value.location
                        }
                        .onEnded { _ in onLinesChanged() }
                }
                endpointHandle(at: line.end) {
                    DragGesture(coordinateSpace: .named("lineboard"))
                        .onChanged { value in
                            guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
                            lines[index].end = value.location
                        }
                        .onEnded { _ in onLinesChanged() }
                }
            }
        }
        .onTapGesture {
            guard !isDrawingEnabled, !isPlacing else { return }
            selectedID = line.id
        }
        .gesture(moveGesture(for: line, canvasSize: canvasSize), including: (!isDrawingEnabled && !isPlacing) ? .gesture : .subviews)
    }

    private func endpointHandle<G: Gesture>(at point: CGPoint, gesture: () -> G) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .frame(width: handleSize, height: handleSize)
            .position(point)
            .highPriorityGesture(gesture())
    }

    private func moveGesture(for line: LineShape, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("lineboard"))
            .onChanged { value in
                guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
                if moveStartLine == nil {
                    moveStartLine = lines[index]
                    selectedID = line.id
                    showTrash = true
                }
                guard let start = moveStartLine else { return }
                lines[index].start = CGPoint(
                    x: start.x1 + value.translation.width,
                    y: start.y1 + value.translation.height
                )
                lines[index].end = CGPoint(
                    x: start.x2 + value.translation.width,
                    y: start.y2 + value.translation.height
                )
                overTrash = trashHitFrame(in: canvasSize).contains(value.location)
            }
            .onEnded { value in
                defer {
                    moveStartLine = nil
                    showTrash = false
                    overTrash = false
                }
                guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
                if trashHitFrame(in: canvasSize).contains(value.location) {
                    let id = lines[index].id
                    lines.remove(at: index)
                    if selectedID == id { selectedID = nil }
                }
                onLinesChanged()
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
                let end = value.location
                guard hypot(end.x - start.x, end.y - start.y) >= 16 else { return }
                let line = LineShape.make(
                    from: start,
                    to: end,
                    colorHex: draftColorHex,
                    width: draftWidth
                )
                lines.append(line)
                selectedID = line.id
                onLinesChanged()
            }
    }
}

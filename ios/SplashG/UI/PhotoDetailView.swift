import SwiftUI
import Kingfisher

/// Full-screen swipeable pager: full-res image, save + share.
struct PhotoDetailView: View {
    let photos: [Photo]
    @State private var index: Int
    @State private var failed = false
    @State private var dragOffset: CGFloat = 0
    @State private var dragAxis: Axis?
    @State private var isZoomed = false
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss

    init(photos: [Photo], initialIndex: Int) {
        self.photos = photos
        _index = State(initialValue: min(max(initialIndex, 0), max(photos.count - 1, 0)))
    }

    private var current: Photo? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    /// Fades chrome + background out as the sheet is pulled down.
    private var dragProgress: CGFloat {
        min(max(dragOffset / 300, 0), 1)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(1 - Double(dragProgress) * 0.9).ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { i, photo in
                    ZoomableImageView(photo: photo, isZoomed: $isZoomed)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragOffset)
            .scaleEffect(1 - dragProgress * 0.12)
        }
        .presentationBackground(.clear)
        // Pull-down to close, Photos-style. simultaneousGesture so the
        // pager keeps horizontal swipes; we only claim downward pulls.
        .simultaneousGesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    guard !isZoomed else { return }
                    let t = value.translation
                    // Lock the gesture's axis at first movement: a page
                    // flip that drifts diagonally must never start
                    // pulling the sheet down mid-swipe.
                    if dragAxis == nil {
                        dragAxis = t.height > abs(t.width) * 1.5 ? .vertical : .horizontal
                    }
                    guard dragAxis == .vertical else { return }
                    dragOffset = max(0, t.height)
                }
                .onEnded { value in
                    defer { dragAxis = nil }
                    guard !isZoomed, dragAxis == .vertical else { return }
                    if dragOffset > 140 || (dragOffset > 50 && value.predictedEndTranslation.height > 320) {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.ultraThinMaterial))
                    .foregroundStyle(.white)
            }
            .padding(.trailing, 20)
            .padding(.top, 8)
            .opacity(1 - Double(dragProgress) * 2)
        }
        .overlay(alignment: .bottom) {
            bottomBar
                .opacity(1 - Double(dragProgress) * 2)
        }
        .onChange(of: index) {
            failed = false
            isZoomed = false
        }
        .statusBarHidden()
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let photo = current {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(photo.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(photo.albumTitle) · \(photo.curator)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer()

                Button {
                    download(photo)
                } label: {
                    Group {
                        if downloads.isDownloaded(photo) {
                            Image(systemName: "checkmark")
                        } else if downloads.isDownloading(photo) {
                            ProgressView().controlSize(.small)
                        } else if failed {
                            Image(systemName: "exclamationmark.triangle")
                        } else {
                            Image(systemName: "arrow.down")
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.ultraThinMaterial))
                    .foregroundStyle(downloads.isDownloaded(photo) ? Color.green : .white)
                }

                ShareLink(item: photo.fullURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(.ultraThinMaterial))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            )
            .foregroundStyle(.white)
        }
    }

    private func download(_ photo: Photo) {
        guard !downloads.isDownloaded(photo), !downloads.isDownloading(photo) else { return }
        failed = false
        Task {
            do { try await downloads.download(photo) } catch { failed = true }
        }
    }
}

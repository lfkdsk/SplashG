import SwiftUI
import Kingfisher

/// Full-screen swipeable pager: full-res image, save + share.
struct PhotoDetailView: View {
    let photos: [Photo]
    @State private var index: Int
    @State private var saveState: PhotoCard.SaveState = .idle
    @Environment(\.dismiss) private var dismiss

    init(photos: [Photo], initialIndex: Int) {
        self.photos = photos
        _index = State(initialValue: min(max(initialIndex, 0), max(photos.count - 1, 0)))
    }

    private var current: Photo? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { i, photo in
                    KFImage(photo.fullURL)
                        .alternativeSources(photo.backupFullURL.map { [.network($0)] } ?? [])
                        .placeholder {
                            KFImage(photo.thumbURL)
                                .resizable()
                                .scaledToFit()
                                .overlay(ProgressView())
                        }
                        .retry(maxCount: 2, interval: .seconds(1))
                        .fade(duration: 0.2)
                        .resizable()
                        .scaledToFit()
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
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
        }
        .overlay(alignment: .bottom) { bottomBar }
        .onChange(of: index) { saveState = .idle }
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

                Button(action: save) {
                    Group {
                        switch saveState {
                        case .idle: Image(systemName: "arrow.down")
                        case .saving: ProgressView().controlSize(.small)
                        case .done: Image(systemName: "checkmark")
                        case .failed: Image(systemName: "exclamationmark.triangle")
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.ultraThinMaterial))
                    .foregroundStyle(saveState == .done ? Color.green : .white)
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

    private func save() {
        guard let photo = current, saveState == .idle || saveState == .failed else { return }
        saveState = .saving
        Task {
            do {
                try await ImageSaver.save(photo)
                saveState = .done
            } catch {
                saveState = .failed
            }
        }
    }
}

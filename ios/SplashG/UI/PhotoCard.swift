import SwiftUI
import Kingfisher

/// Waterfall cell: cropped thumbnail with a floating download button,
/// like the MyerSplash editor feed.
struct PhotoCard: View {
    let photo: Photo
    var onTap: () -> Void

    @State private var saveState: SaveState = .idle

    enum SaveState { case idle, saving, done, failed }

    var body: some View {
        Color.clear
            .aspectRatio(photo.aspect, contentMode: .fit)
            .overlay {
                KFImage(photo.thumbURL)
                    .alternativeSources(photo.backupThumbURL.map { [.network($0)] } ?? [])
                    .placeholder { Rectangle().fill(Theme.card) }
                    .retry(maxCount: 2, interval: .seconds(1))
                    .fade(duration: 0.25)
                    .cancelOnDisappear(true)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomTrailing) { downloadButton }
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onTapGesture(perform: onTap)
    }

    private var downloadButton: some View {
        Button {
            guard saveState == .idle || saveState == .failed else { return }
            saveState = .saving
            Task {
                do {
                    try await ImageSaver.save(photo)
                    saveState = .done
                } catch {
                    saveState = .failed
                }
            }
        } label: {
            Group {
                switch saveState {
                case .idle: Image(systemName: "arrow.down")
                case .saving: ProgressView().controlSize(.mini)
                case .done: Image(systemName: "checkmark")
                case .failed: Image(systemName: "exclamationmark.triangle")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 32, height: 32)
            .background(Circle().fill(.ultraThinMaterial))
            .foregroundStyle(saveState == .done ? Color.green : .white)
        }
        .padding(8)
    }
}

import SwiftUI

/// Lists the user's GitHub repos so one can be bound as a gallery.
/// The backend validates the album_template shape (README.yml) on bind.
struct RepoPickerView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    var onPick: (GHRepo) async -> Void

    @State private var repos: [GHRepo] = []
    @State private var loading = true
    @State private var filter = ""
    @State private var binding: Int?   // repo id currently being bound
    @State private var error: String?

    private var filtered: [GHRepo] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return repos }
        return repos.filter { $0.fullName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .listRowBackground(Theme.card)
                }
                ForEach(filtered) { repo in
                    Button {
                        binding = repo.id
                        Task {
                            await onPick(repo)
                            binding = nil
                            dismiss()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.fullName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                if let desc = repo.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(Theme.subtle)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if binding == repo.id {
                                ProgressView().controlSize(.small)
                            } else if repo.isPrivate {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtle)
                            }
                        }
                    }
                    .disabled(binding != nil)
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .searchable(text: $filter, prompt: "Filter repos")
            .overlay {
                if loading {
                    ProgressView()
                } else if filtered.isEmpty {
                    Text("No repos found")
                        .foregroundStyle(Theme.subtle)
                }
            }
            .navigationTitle("Pick a repo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let token = auth.token else { return }
        defer { loading = false }
        do {
            repos = try await GitHubAPI(token: token).repos()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

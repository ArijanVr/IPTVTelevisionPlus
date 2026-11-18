import ARJOCore
import SwiftUI

struct MovieDetailView: View {
    @State private var model: MovieDetailModel
    private let player: VODPlayerModel

    init(item: VODItem, catalog: VODCatalogModel, player: VODPlayerModel) {
        _model = State(initialValue: MovieDetailModel(item: item, catalog: catalog, player: player))
        self.player = player
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 32) {
                PosterCard(title: "", posterURL: model.item.posterURL, fraction: model.progress?.fraction ?? 0, isWatched: model.isWatched)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 16) {
                    Text(model.item.name).font(.arjo(.display))
                    if !metaLine.isEmpty { Text(metaLine).foregroundStyle(.secondary) }
                    actions
                    switch model.phase {
                    case .loading:
                        ProgressView()
                    case .failed(let message):
                        Text("Details nicht verfügbar: \(message)").foregroundStyle(.secondary)
                    case .ready:
                        if let plot = model.detail?.plot { Text(plot) }
                        if let cast = model.detail?.cast { labeled("Besetzung", cast) }
                        if let director = model.detail?.director { labeled("Regie", director) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(48)
        }
        .navigationTitle(model.item.name)
        .task { await model.load() }
        .task(id: player.progressRevision) { await model.reloadProgress() }
    }

    private var metaLine: String {
        let detail = model.detail
        return [
            detail?.releaseDate.map { String($0.prefix(4)) } ?? model.item.year,
            detail?.durationSeconds.flatMap(Formatting.duration(seconds:)),
            (detail?.rating ?? model.item.rating).map(Formatting.rating),
            detail?.genre,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Button {
                Task { await model.play() }
            } label: {
                Label(
                    model.resumePosition.map { String(localized: "Fortsetzen ab \(Formatting.clock($0))") } ?? String(localized: "Abspielen"),
                    systemImage: "play.fill"
                )
            }

            Button {
                Task { await model.toggleWatched() }
            } label: {
                Label(
                    model.isWatched ? String(localized: "Als nicht gesehen markieren") : String(localized: "Als gesehen markieren"),
                    systemImage: model.isWatched ? "eye.slash" : "checkmark.circle"
                )
            }
        }
    }

    private func labeled(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.arjo(.small)).foregroundStyle(.secondary)
            Text(text)
        }
    }
}

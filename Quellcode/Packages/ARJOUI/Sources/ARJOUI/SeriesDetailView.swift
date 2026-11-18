import ARJOCore
import SwiftUI

struct SeriesDetailView: View {
    @State private var model: SeriesDetailModel
    private let player: VODPlayerModel

    init(item: VODItem, catalog: VODCatalogModel, player: VODPlayerModel) {
        _model = State(initialValue: SeriesDetailModel(item: item, catalog: catalog, player: player))
        self.player = player
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed(let message):
                    Text("Details nicht verfügbar: \(message)").foregroundStyle(.secondary)
                case .ready where model.seasons.isEmpty:
                    Text("Für diese Serie sind keine Episoden vorhanden.").foregroundStyle(.secondary)
                case .ready:
                    seasonPicker
                    LazyVStack(spacing: 12) {
                        ForEach(model.episodes) { episode in
                            EpisodeRow(episode: episode, model: model)
                        }
                    }
                }
            }
            .padding(48)
        }
        .navigationTitle(model.item.name)
        .task { await model.load() }
        .task(id: player.progressRevision) { await model.reloadProgress() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 32) {
            PosterCard(title: "", posterURL: model.item.posterURL).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(model.item.name).font(.arjo(.display))
                let meta = [
                    model.detail?.releaseDate.map { String($0.prefix(4)) } ?? model.item.year,
                    (model.detail?.rating ?? model.item.rating).map(Formatting.rating),
                    model.detail?.genre,
                ].compactMap { $0 }.joined(separator: " · ")
                if !meta.isEmpty { Text(meta).foregroundStyle(.secondary) }
                if let plot = model.detail?.plot { Text(plot) }
                if let cast = model.detail?.cast {
                    Text("Besetzung: \(cast)").font(.arjo(.body)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var seasonPicker: some View {
        Picker("Staffel", selection: $model.selectedSeason) {
            ForEach(model.seasons) { season in
                Text("Staffel \(season.number)").tag(Optional(season.number))
            }
        }
        .pickerStyle(.menu)
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let model: SeriesDetailModel

    var body: some View {
        Button {
            Task { await model.play(episode) }
        } label: {
            HStack(spacing: 16) {
                Text("\(episode.episodeNumber)")
                    .font(.arjo(.micro))
                    .foregroundStyle(.secondary)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title).font(.arjo(.headline)).lineLimit(1)
                    if let plot = episode.plot {
                        Text(plot).font(.arjo(.small)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let duration = episode.durationSeconds.flatMap(Formatting.duration(seconds:)) {
                        Text(duration).font(.arjo(.small)).foregroundStyle(.secondary)
                    }
                    let fraction = model.fraction(episode)
                    if fraction > 0, fraction < 1 {
                        ProgressView(value: fraction).tint(Theme.glut)
                    }
                }
                Spacer(minLength: 0)
                if model.isWatched(episode) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Gesehen")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.fieldRadius))
        .contextMenu {
            Button(LocalizedStringKey(model.isWatched(episode) ? "Als nicht gesehen markieren" : "Als gesehen markieren")) {
                Task { await model.toggleWatched(episode) }
            }
        }
    }
}

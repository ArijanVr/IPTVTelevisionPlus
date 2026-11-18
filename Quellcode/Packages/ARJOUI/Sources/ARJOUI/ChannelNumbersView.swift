import ARJOCore
import SwiftUI

/// Einstellungen › Kanalnummern: Nummer eines Senders ändern (bei Konflikt tauschen) oder nach Gruppen neu nummerieren.
struct ChannelNumbersView: View {
    let live: LiveTVViewModel
    let organization: OrganizationModel
    @State private var query = ""
    @State private var results: [Channel] = []
    @State private var editing: Channel?
    @State private var text = ""
    @State private var confirmsRenumber = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                TextField("Sender suchen", text: $query)
                    .onSubmit { Task { await search() } }
                    .onChange(of: query) { Task { await search() } }
            }
            Section {
                ForEach(results) { channel in
                    Button { editing = channel; text = channel.number.map(String.init) ?? "" } label: {
                        HStack {
                            Text(verbatim: channel.number.map(String.init) ?? "–").monospacedDigit().frame(minWidth: 56, alignment: .trailing)
                            Text(verbatim: organization.name(for: channel)).lineLimit(1)
                        }
                    }
                    .accessibilityLabel("\(channel.number ?? 0) \(organization.name(for: channel))")
                }
            } footer: {
                Text(message ?? String(localized: "Ist eine Nummer vergeben, tauschen beide Sender ihre Nummern."))
            }
            Section {
                Button("Neu nummerieren nach Gruppen", role: .destructive) { confirmsRenumber = true }
            } footer: {
                Text("Alle Sender werden ab 1 neu nummeriert, Gruppe für Gruppe in deiner Reihenfolge.")
            }
        }
        .navigationTitle("Kanalnummern")
        .alert("Kanalnummer", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Nummer", text: $text)
                #if !os(macOS)
                .keyboardType(.numberPad)
                #endif
            Button("Speichern") { Task { await save() } }
            Button("Abbrechen", role: .cancel) { editing = nil }
        }
        .confirmationDialog("Alle Sender neu nummerieren?", isPresented: $confirmsRenumber) {
            Button("Neu nummerieren", role: .destructive) { Task { await renumber() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Eigene Nummern gehen verloren.")
        }
    }

    private func search() async {
        results = (try? await live.searchChannels(query, limit: 40)) ?? []
    }

    private func save() async {
        defer { editing = nil }
        guard let channel = editing, let number = Int(text), number >= 1 else { return }
        _ = await live.setNumber(number, for: channel)
        await search()
    }

    private func renumber() async {
        let order = organization.visible(live.groups, in: .live).map(\.name)
        await live.renumberByGroups(order)
        message = String(localized: "Neu nummeriert.")
        await search()
    }
}

#if os(tvOS)
import ARJOCore
import ARJOData
import TVServices

/// Top-Shelf-Erweiterung: zeigt «Weiterschauen» auf dem Apple-TV-Home-Bildschirm.
/// Gehört in ein eigenes Target (tvOS › TV Top Shelf Extension) mit derselben App Group wie die App.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let store = TopShelfStore.appGroup(), let snapshot = try? store.read(), !snapshot.items.isEmpty else {
            return nil
        }

        let items = snapshot.items.map { item -> TVTopShelfSectionedItem in
            let entry = TVTopShelfSectionedItem(identifier: item.id)
            entry.title = item.title
            entry.imageShape = .poster
            entry.playbackProgress = item.progress
            if let imageURL = item.imageURL {
                entry.setImageURL(imageURL, for: .screenScale1x)
                entry.setImageURL(imageURL, for: .screenScale2x)
            }
            entry.playAction = TVTopShelfAction(url: item.deepLink)
            entry.displayAction = TVTopShelfAction(url: item.deepLink)
            return entry
        }
        let collection = TVTopShelfItemCollection(items: items)
        collection.title = "Weiterschauen"
        return TVTopShelfSectionedContent(sections: [collection])
    }
}
#endif

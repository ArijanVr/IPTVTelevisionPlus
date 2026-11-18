import Foundation

/// Nur die Felder, die der Katalog braucht: bei 50'000 Sendern hält das den Speicher klein.
/// Dekodiert mit `.convertFromSnakeCase`.
struct XtreamCategoryDTO: Decodable {
    var categoryId: LossyString
    var categoryName: String?
}

struct XtreamLiveStreamDTO: Decodable {
    var streamId: LossyString
    var num: LossyString?
    var name: String?
    var streamIcon: String?
    var epgChannelId: String?
    var categoryId: LossyString?
    var tvArchive: LossyString?
    var tvArchiveDuration: LossyString?
}

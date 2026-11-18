import Foundation

/// Xtream-Server liefern Zahlen mal als Zahl, mal als String; hier wird alles zu String.
struct LossyString: Decodable, Equatable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = bool ? "1" : "0"
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Weder Text noch Zahl")
            )
        }
    }
}

/// Dekodiert mit `.convertFromSnakeCase`.
struct XtreamLoginResponse: Decodable {
    struct UserInfo: Decodable {
        var username: LossyString?
        var auth: LossyString?
        var status: LossyString?
        var expDate: LossyString?
        var isTrial: LossyString?
        var activeCons: LossyString?
        var maxConnections: LossyString?
        var allowedOutputFormats: [String]?
    }

    struct ServerInfo: Decodable {
        var timezone: LossyString?
    }

    var userInfo: UserInfo?
    var serverInfo: ServerInfo?
}

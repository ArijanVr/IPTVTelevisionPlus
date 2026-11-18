import ARJOCore
import Foundation

public enum XMLTVError: Error, Equatable {
    case unreadableFile(URL)
    case malformed(line: Int, reason: String)
}

/// Liest XMLTV als Strom (SAX) und übergibt Sender und Sendungen einzeln.
/// Läuft synchron: vom Aufrufer auf einem Hintergrund-Thread bzw. Actor starten.
/// Gzip-Dateien müssen vorher entpackt werden.
public enum XMLTVParser {
    public static func parse(
        fileURL: URL,
        onChannel: @escaping (EPGChannel) -> Void,
        onProgramme: @escaping (EPGProgramme) -> Void
    ) throws {
        guard let stream = InputStream(url: fileURL) else { throw XMLTVError.unreadableFile(fileURL) }
        try parse(stream: stream, onChannel: onChannel, onProgramme: onProgramme)
    }

    public static func parse(
        stream: InputStream,
        onChannel: @escaping (EPGChannel) -> Void,
        onProgramme: @escaping (EPGProgramme) -> Void
    ) throws {
        let parser = XMLParser(stream: stream)
        parser.shouldResolveExternalEntities = false
        let delegate = Delegate(onChannel: onChannel, onProgramme: onProgramme)
        parser.delegate = delegate
        guard parser.parse() else {
            throw XMLTVError.malformed(
                line: parser.lineNumber,
                reason: parser.parserError?.localizedDescription ?? "unbekannter Fehler"
            )
        }
    }
}

private final class Delegate: NSObject, XMLParserDelegate {
    private struct ChannelBuilder {
        var id: String
        var displayName: String?
        var iconURL: URL?
    }

    private struct ProgrammeBuilder {
        var channelID: String
        var start: Date?
        var stop: Date?
        var title: String?
        var subtitle: String?
        var description: String?
        var category: String?
        var iconURL: URL?
    }

    private let onChannel: (EPGChannel) -> Void
    private let onProgramme: (EPGProgramme) -> Void
    private var channel: ChannelBuilder?
    private var programme: ProgrammeBuilder?
    private var text = ""

    init(onChannel: @escaping (EPGChannel) -> Void, onProgramme: @escaping (EPGProgramme) -> Void) {
        self.onChannel = onChannel
        self.onProgramme = onProgramme
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
        text = ""
        switch elementName {
        case "channel":
            channel = ChannelBuilder(id: attributeDict["id"] ?? "")
        case "programme":
            programme = ProgrammeBuilder(
                channelID: attributeDict["channel"] ?? "",
                start: attributeDict["start"].flatMap(XMLTVDate.parse),
                stop: attributeDict["stop"].flatMap(XMLTVDate.parse)
            )
        case "icon":
            let url = attributeDict["src"].flatMap { URL(string: $0) }
            if var current = programme {
                current.iconURL = current.iconURL ?? url
                programme = current
            } else if var current = channel {
                current.iconURL = current.iconURL ?? url
                channel = current
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "display-name":
            if channel != nil, channel?.displayName == nil, !value.isEmpty { channel?.displayName = value }
        case "title":
            if programme != nil, programme?.title == nil, !value.isEmpty { programme?.title = value }
        case "sub-title":
            if programme?.subtitle == nil, !value.isEmpty { programme?.subtitle = value }
        case "desc":
            if programme?.description == nil, !value.isEmpty { programme?.description = value }
        case "category":
            if programme?.category == nil, !value.isEmpty { programme?.category = value }
        case "channel":
            if let built = channel, !built.id.isEmpty {
                onChannel(EPGChannel(id: built.id, displayName: built.displayName ?? built.id, iconURL: built.iconURL))
            }
            channel = nil
        case "programme":
            if let built = programme, !built.channelID.isEmpty,
               let start = built.start, let stop = built.stop, let title = built.title {
                onProgramme(EPGProgramme(
                    channelID: built.channelID, start: start, stop: stop, title: title,
                    subtitle: built.subtitle, description: built.description,
                    category: built.category, iconURL: built.iconURL
                ))
            }
            programme = nil
        default:
            break
        }
        text = ""
    }
}

import Foundation

struct CatastroParcel {
    let refcat: String?
    let areaValue: Double?
    let areaUom: String?
    let label: String?
    let rings: [[Coordinate]]
}

enum CatastroError: Error, LocalizedError {
    case invalidRefcat
    case invalidResponse
    case noGeometry

    var errorDescription: String? {
        switch self {
        case .invalidRefcat:
            return "Invalid cadastral reference. Use 14 characters."
        case .invalidResponse:
            return "Unexpected response from Catastro service."
        case .noGeometry:
            return "No parcel geometry returned for this reference."
        }
    }
}

final class CatastroService {
    static let shared = CatastroService()

    private init() {}

    func fetchParcel(refcat14: String) async throws -> CatastroParcel {
        let cleaned = refcat14.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleaned.count == 14 else {
            throw CatastroError.invalidRefcat
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "ovc.catastro.meh.es"
        components.path = "/INSPIRE/wfsCP.aspx"
        components.queryItems = [
            URLQueryItem(name: "service", value: "wfs"),
            URLQueryItem(name: "version", value: "2.0.0"),
            URLQueryItem(name: "request", value: "GetFeature"),
            URLQueryItem(name: "STOREDQUERIE_ID", value: "GetParcel"),
            URLQueryItem(name: "refcat", value: cleaned),
            URLQueryItem(name: "srsname", value: "EPSG:4326")
        ]

        guard let url = components.url else {
            throw CatastroError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CatastroError.invalidResponse
        }

        let parser = CatastroParcelParser(data: data)
        let parcel = try parser.parse()
        guard !parcel.rings.isEmpty else {
            throw CatastroError.noGeometry
        }
        return parcel
    }
}

private final class CatastroParcelParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var currentText = ""
    private var currentElement: String = ""

    private var refcat: String?
    private var areaValue: Double?
    private var areaUom: String?
    private var label: String?
    private var rings: [[Coordinate]] = []

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() throws -> CatastroParcel {
        guard parser.parse() else {
            throw parser.parserError ?? CatastroError.invalidResponse
        }
        return CatastroParcel(refcat: refcat, areaValue: areaValue, areaUom: areaUom, label: label, rings: rings)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = localName(from: qName ?? elementName)
        currentText = ""

        if currentElement == "areaValue" {
            areaUom = attributeDict["uom"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(from: qName ?? elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "posList":
            if let ring = parseRing(from: text) {
                rings.append(ring)
            }
        case "pos":
            if let ring = parseRing(from: text) {
                rings.append(ring)
            }
        case "nationalCadastralReference", "reference":
            if !text.isEmpty { refcat = text }
        case "areaValue":
            if let value = Double(text) { areaValue = value }
        case "label":
            if !text.isEmpty { label = text }
        default:
            break
        }
    }

    private func localName(from qualified: String) -> String {
        if let idx = qualified.firstIndex(of: ":") {
            return String(qualified[qualified.index(after: idx)...])
        }
        return qualified
    }

    private func parseRing(from text: String) -> [Coordinate]? {
        let parts = text.split { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count >= 4, numbers.count % 2 == 0 else { return nil }

        var ring: [Coordinate] = []
        ring.reserveCapacity(numbers.count / 2)

        var i = 0
        while i < numbers.count {
            let a = numbers[i]
            let b = numbers[i + 1]
            let coordinate = toCoordinate(a: a, b: b)
            ring.append(coordinate)
            i += 2
        }

        if let first = ring.first, let last = ring.last, first != last {
            ring.append(first)
        }

        return ring
    }

    private func toCoordinate(a: Double, b: Double) -> Coordinate {
        // Heuristic for Spain: lon is typically between -15 and 15, lat between 35 and 45.
        let looksLikeLonLat = abs(a) <= 15 && b >= 35 && b <= 45
        let looksLikeLatLon = abs(b) <= 15 && a >= 35 && a <= 45

        if looksLikeLonLat {
            return Coordinate(latitude: b, longitude: a)
        }
        if looksLikeLatLon {
            return Coordinate(latitude: a, longitude: b)
        }

        // Fallback: swap if first value cannot be latitude.
        if abs(a) > 90 && abs(b) <= 90 {
            return Coordinate(latitude: b, longitude: a)
        }

        return Coordinate(latitude: a, longitude: b)
    }
}

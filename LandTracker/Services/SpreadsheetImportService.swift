import Foundation
import SwiftData
import CryptoKit

enum SpreadsheetImportError: LocalizedError {
    case unsupportedEncoding
    case missingHeader
    case missingKeyColumn
    case missingPeriodColumns

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding:
            return "No se pudo leer el archivo. Usa CSV UTF-8 exportado desde Excel."
        case .missingHeader:
            return "No se detecto cabecera en el CSV."
        case .missingKeyColumn:
            return "Falta una columna clave (refcat/catastro o nombre de terreno)."
        case .missingPeriodColumns:
            return "Faltan columnas de periodo (anio y mes)."
        }
    }
}

struct SpreadsheetImportSummary {
    let processedRows: Int
    let linkedRows: Int
    let unmatchedRows: Int
    let skippedByManualConflict: Int
    let createdEntries: Int
}

final class SpreadsheetImportService {
    static let shared = SpreadsheetImportService()

    private init() {}

    static func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    func importCSVData(_ data: Data, context: ModelContext) throws -> SpreadsheetImportSummary {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw SpreadsheetImportError.unsupportedEncoding
        }

        let delimiter = detectDelimiter(text)
        let rows = parseCSVRows(text: text, delimiter: delimiter)
            .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

        guard let header = rows.first else {
            throw SpreadsheetImportError.missingHeader
        }

        let headerMap = buildHeaderMap(header)
        let refcatIndex = firstColumnIndex(
            from: ["refcat", "refcat14", "catastro", "catastro_refcat14", "parcel", "parcel_code", "parcelcode"],
            map: headerMap
        )
        let landNameIndex = firstColumnIndex(
            from: ["land_name", "land", "finca", "terreno", "nombre_finca", "nombre_terreno", "name"],
            map: headerMap
        )
        guard refcatIndex != nil || landNameIndex != nil else {
            throw SpreadsheetImportError.missingKeyColumn
        }

        let yearIndex = firstColumnIndex(from: ["year", "anio", "ano"], map: headerMap)
        let monthIndex = firstColumnIndex(from: ["month", "mes"], map: headerMap)
        let periodIndex = firstColumnIndex(from: ["period", "fecha", "date"], map: headerMap)
        guard (yearIndex != nil && monthIndex != nil) || periodIndex != nil else {
            throw SpreadsheetImportError.missingPeriodColumns
        }

        let incomeIndex = firstColumnIndex(from: ["income", "ingresos", "income_amount"], map: headerMap)
        let productionIndex = firstColumnIndex(from: ["production", "produccion", "production_amount"], map: headerMap)
        let productionUnitIndex = firstColumnIndex(from: ["production_unit", "unidad", "unit"], map: headerMap)
        let electricityIndex = firstColumnIndex(from: ["electricity", "electricidad", "electricity_kwh", "kwh"], map: headerMap)
        let notesIndex = firstColumnIndex(from: ["notes", "nota", "notas", "comentarios"], map: headerMap)

        let lands = (try? context.fetch(FetchDescriptor<Land>())) ?? []
        var landsByRefcat: [String: Land] = [:]
        var landsByName: [String: Land] = [:]
        for land in lands {
            if let refcat = normalizedKey(land.catastroRefcat14), landsByRefcat[refcat] == nil {
                landsByRefcat[refcat] = land
            }

            let nameKey = normalizedName(land.name)
            if !nameKey.isEmpty, landsByName[nameKey] == nil {
                landsByName[nameKey] = land
            }
        }

        let allExistingEntries = (try? context.fetch(FetchDescriptor<LandHistoryEntry>())) ?? []
        let spreadsheetEntries = allExistingEntries.filter { $0.source == .spreadsheet }
        let landsTouchedByDeletedSpreadsheetEntries = Set(spreadsheetEntries.compactMap { $0.land?.id })
        for entry in spreadsheetEntries {
            context.delete(entry)
        }

        let manualPeriodsByLand = Dictionary(
            uniqueKeysWithValues: lands.map { land in
                let periods = Set(
                    land.historyEntries
                        .filter { $0.source == .manual }
                        .map(\.periodKey)
                )
                return (land.id, periods)
            }
        )

        struct ParsedRecord {
            let land: Land
            let year: Int
            let month: Int
            let incomeAmount: Double
            let productionAmount: Double
            let productionUnit: String
            let electricityKWh: Double
            let notes: String
        }

        var parsedRecordsByLandPeriod: [String: ParsedRecord] = [:]
        var processedRows = 0
        var unmatchedRows = 0
        var skippedByManualConflict = 0

        for row in rows.dropFirst() {
            processedRows += 1

            let refcatValue = cellValue(row, index: refcatIndex)
            let landNameValue = cellValue(row, index: landNameIndex)
            let land = resolveLand(
                refcatValue: refcatValue,
                landNameValue: landNameValue,
                landsByRefcat: landsByRefcat,
                landsByName: landsByName
            )

            guard let land else {
                unmatchedRows += 1
                continue
            }

            guard let period = parsePeriod(
                yearText: cellValue(row, index: yearIndex),
                monthText: cellValue(row, index: monthIndex),
                periodText: cellValue(row, index: periodIndex)
            ) else {
                continue
            }

            if manualPeriodsByLand[land.id]?.contains(period.periodKey) == true {
                skippedByManualConflict += 1
                continue
            }

            let parsed = ParsedRecord(
                land: land,
                year: period.year,
                month: period.month,
                incomeAmount: parseNumber(cellValue(row, index: incomeIndex)) ?? 0,
                productionAmount: parseNumber(cellValue(row, index: productionIndex)) ?? 0,
                productionUnit: {
                    let raw = cellValue(row, index: productionUnitIndex).trimmingCharacters(in: .whitespacesAndNewlines)
                    return raw.isEmpty ? "t" : raw
                }(),
                electricityKWh: parseNumber(cellValue(row, index: electricityIndex)) ?? 0,
                notes: cellValue(row, index: notesIndex)
            )

            let key = "\(land.id.uuidString)-\(period.periodKey)"
            parsedRecordsByLandPeriod[key] = parsed
        }

        for record in parsedRecordsByLandPeriod.values {
            let entry = LandHistoryEntry(
                year: record.year,
                month: record.month,
                incomeAmount: max(0, record.incomeAmount),
                productionAmount: max(0, record.productionAmount),
                productionUnit: record.productionUnit,
                electricityKWh: max(0, record.electricityKWh),
                notes: record.notes,
                source: .spreadsheet,
                land: record.land
            )
            context.insert(entry)
        }

        let affectedLandIDs = Set(parsedRecordsByLandPeriod.values.map { $0.land.id })
            .union(landsTouchedByDeletedSpreadsheetEntries)

        for land in lands where affectedLandIDs.contains(land.id) {
            recalculateAnnualSummaries(for: land)
        }

        try context.save()

        return SpreadsheetImportSummary(
            processedRows: processedRows,
            linkedRows: parsedRecordsByLandPeriod.count,
            unmatchedRows: unmatchedRows,
            skippedByManualConflict: skippedByManualConflict,
            createdEntries: parsedRecordsByLandPeriod.count
        )
    }

    private func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        let candidates: [Character] = [",", ";", "\t"]
        let scored = candidates.map { delimiter in
            (delimiter, firstLine.filter { $0 == delimiter }.count)
        }
        return scored.max(by: { $0.1 < $1.1 })?.0 ?? ","
    }

    private func parseCSVRows(text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false

        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if isInsideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == delimiter, !isInsideQuotes {
                row.append(field)
                field = ""
            } else if character == "\n", !isInsideQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }

            index += 1
        }

        row.append(field)
        if row.contains(where: { !$0.isEmpty }) {
            rows.append(row)
        }

        return rows
    }

    private func buildHeaderMap(_ header: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (index, value) in header.enumerated() {
            map[normalizeHeader(value)] = index
        }
        return map
    }

    private func normalizeHeader(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func firstColumnIndex(from candidates: [String], map: [String: Int]) -> Int? {
        for candidate in candidates {
            if let index = map[normalizeHeader(candidate)] {
                return index
            }
        }
        return nil
    }

    private func cellValue(_ row: [String], index: Int?) -> String {
        guard let index, row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.uppercased()
    }

    private func normalizedName(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func resolveLand(
        refcatValue: String,
        landNameValue: String,
        landsByRefcat: [String: Land],
        landsByName: [String: Land]
    ) -> Land? {
        if let refcat = normalizedKey(refcatValue), let land = landsByRefcat[refcat] {
            return land
        }

        let nameKey = normalizedName(landNameValue)
        guard !nameKey.isEmpty else { return nil }
        return landsByName[nameKey]
    }

    private func parsePeriod(yearText: String, monthText: String, periodText: String) -> (year: Int, month: Int, periodKey: Int)? {
        if let year = Int(yearText), let month = parseMonth(monthText), (2000...2100).contains(year), (1...12).contains(month) {
            return (year, month, year * 100 + month)
        }

        let raw = periodText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy-MM", "yyyy/MM", "MM/yyyy", "MM-yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                let calendar = Calendar.current
                let year = calendar.component(.year, from: date)
                let month = calendar.component(.month, from: date)
                if (2000...2100).contains(year), (1...12).contains(month) {
                    return (year, month, year * 100 + month)
                }
            }
        }

        return nil
    }

    private func parseMonth(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(trimmed), (1...12).contains(number) {
            return number
        }

        let normalized = trimmed
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        let months: [String: Int] = [
            "january": 1, "jan": 1, "enero": 1,
            "february": 2, "feb": 2, "febrero": 2,
            "march": 3, "mar": 3, "marzo": 3,
            "april": 4, "apr": 4, "abril": 4,
            "may": 5, "mayo": 5,
            "june": 6, "jun": 6, "junio": 6,
            "july": 7, "jul": 7, "julio": 7,
            "august": 8, "aug": 8, "agosto": 8,
            "september": 9, "sep": 9, "sept": 9, "septiembre": 9,
            "october": 10, "oct": 10, "octubre": 10,
            "november": 11, "nov": 11, "noviembre": 11,
            "december": 12, "dec": 12, "diciembre": 12
        ]
        return months[normalized]
    }

    private func parseNumber(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var sanitized = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")

        let hasComma = sanitized.contains(",")
        let hasDot = sanitized.contains(".")
        if hasComma && hasDot {
            if (sanitized.lastIndex(of: ",") ?? sanitized.startIndex) > (sanitized.lastIndex(of: ".") ?? sanitized.startIndex) {
                sanitized = sanitized.replacingOccurrences(of: ".", with: "")
                sanitized = sanitized.replacingOccurrences(of: ",", with: ".")
            } else {
                sanitized = sanitized.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            sanitized = sanitized.replacingOccurrences(of: ",", with: ".")
        }

        return Double(sanitized)
    }

    private func recalculateAnnualSummaries(for land: Land) {
        let latestEntries = Dictionary(grouping: land.historyEntries, by: \.periodKey)
            .compactMap { _, entries in
                entries.max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
            }
            .sorted { lhs, rhs in lhs.periodKey > rhs.periodKey }
            .prefix(12)

        land.incomeAnnual = latestEntries.reduce(0) { $0 + max(0, $1.incomeAmount) }
        land.annualElectricityProductionKWh = latestEntries.reduce(0) { $0 + max(0, $1.electricityKWh) }
    }
}

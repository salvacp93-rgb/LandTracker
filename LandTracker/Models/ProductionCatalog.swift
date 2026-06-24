import Foundation

struct ActivityTypeItem: Identifiable, Hashable {
    let name: String
    let includesEnergyMetrics: Bool

    var id: String { name }

    func displayName(language: AppLanguage) -> String {
        ActivityCatalog.displayName(for: name, language: language)
    }
}

enum ActivityCatalog {
    static let agricultural = "Agricultural Operation"
    static let agrovoltaic = "Agrovoltaic"
    static let electricGeneration = "Electric Generation"
    static let livestock = "Livestock"
    static let forestry = "Forestry"
    static let mixedUse = "Mixed Use"

    static let items: [ActivityTypeItem] = [
        ActivityTypeItem(name: agricultural, includesEnergyMetrics: false),
        ActivityTypeItem(name: agrovoltaic, includesEnergyMetrics: true),
        ActivityTypeItem(name: electricGeneration, includesEnergyMetrics: true),
        ActivityTypeItem(name: mixedUse, includesEnergyMetrics: false)
    ]

    static var defaultName: String { agricultural }

    static func item(for name: String) -> ActivityTypeItem? {
        let canonical = canonicalKey(for: name)
        return items.first { canonicalKey(for: $0.name) == canonical }
    }

    static func supportsEnergyMetrics(activityType: String) -> Bool {
        item(for: activityType)?.includesEnergyMetrics ?? false
    }

    static func supportsCropCatalog(activityType: String) -> Bool {
        switch canonicalKey(for: activityType) {
        case canonicalKey(for: agricultural),
            canonicalKey(for: agrovoltaic),
            canonicalKey(for: mixedUse):
            return true
        default:
            return false
        }
    }

    static func displayName(for name: String, language: AppLanguage) -> String {
        switch canonicalKey(for: name) {
        case canonicalKey(for: agricultural):
            return language.localized("Agriculture", "Agricultura")
        case canonicalKey(for: agrovoltaic):
            return language.localized("Agrovoltaic", "Agrovoltaica")
        case canonicalKey(for: electricGeneration):
            return language.localized("Electric Generation", "Generacion electrica")
        case canonicalKey(for: livestock):
            return language.localized("Livestock", "Ganaderia")
        case canonicalKey(for: forestry):
            return language.localized("Forestry", "Forestal")
        case canonicalKey(for: mixedUse):
            return language.localized("Mixed Use", "Uso mixto")
        default:
            return name
        }
    }

    private static func canonicalKey(for name: String) -> String {
        let normalized = normalizeCatalogKey(name)
        switch normalized {
        case normalizeCatalogKey(agricultural),
            normalizeCatalogKey("Agriculture"),
            normalizeCatalogKey("Agricultura"),
            normalizeCatalogKey("Explotacion agricola"):
            return normalizeCatalogKey(agricultural)
        case normalizeCatalogKey(agrovoltaic),
            normalizeCatalogKey("Agrovoltaica"):
            return normalizeCatalogKey(agrovoltaic)
        case normalizeCatalogKey(electricGeneration),
            normalizeCatalogKey("Generacion electrica"),
            normalizeCatalogKey("Generacion de electricidad"):
            return normalizeCatalogKey(electricGeneration)
        case normalizeCatalogKey(livestock),
            normalizeCatalogKey("Ganaderia"):
            return normalizeCatalogKey(livestock)
        case normalizeCatalogKey(forestry),
            normalizeCatalogKey("Forestal"):
            return normalizeCatalogKey(forestry)
        case normalizeCatalogKey(mixedUse),
            normalizeCatalogKey("Uso mixto"):
            return normalizeCatalogKey(mixedUse)
        default:
            return normalized
        }
    }
}

struct ProductionTypeItem: Identifiable, Hashable {
    let name: String
    let varieties: [String]
    let colorHex: String
    let aliases: [String]

    var id: String { name }

    func displayName(language: AppLanguage) -> String {
        ProductionCatalog.displayName(for: name, language: language)
    }
}

enum ProductionCatalog {
    static let other = "Other"
    static let vegetables = "Vegetables"
    static let melonsAndWatermelons = "Melons and Watermelons"
    static let cereals = "Cereals"
    static let legumes = "Legumes"
    static let industrialCrops = "Industrial and Oil Crops"
    static let forageCrops = "Forage Crops"
    static let citrus = "Citrus"
    static let stoneFruits = "Stone Fruits"
    static let pomeFruits = "Pome Fruits"
    static let nuts = "Nuts"
    static let berries = "Berries"
    static let tropicalFruits = "Tropical Fruits"
    static let otherFruitTrees = "Other Fruit Trees"
    static let vineyard = "Vineyard"
    static let oliveGrove = "Olive Grove"
    static let flowersAndOrnamentals = "Flowers and Ornamentals"

    static let items: [ProductionTypeItem] = [
        ProductionTypeItem(
            name: vegetables,
            varieties: [
                "Tomato", "Cherry Tomato", "Pepper", "Eggplant", "Cucumber", "Zucchini",
                "Pumpkin", "Lettuce", "Spinach", "Chard", "Celery", "Endive", "Broccoli",
                "Cauliflower", "Cabbage", "Artichoke", "Asparagus", "Onion", "Garlic",
                "Leek", "Carrot", "Turnip", "Green Bean", "Green Pea", "Mushroom", other
            ],
            colorHex: "2D9C5A",
            aliases: ["Hortalizas", "Horticolas"]
        ),
        ProductionTypeItem(
            name: melonsAndWatermelons,
            varieties: ["Melon", "Watermelon", other],
            colorHex: "27C28A",
            aliases: ["Melon y Sandia", "Melones y Sandias"]
        ),
        ProductionTypeItem(
            name: cereals,
            varieties: ["Soft Wheat", "Durum Wheat", "Barley", "Oats", "Rye", "Corn", "Rice", "Triticale", "Sorghum", other],
            colorHex: "C89A38",
            aliases: ["Cereales"]
        ),
        ProductionTypeItem(
            name: legumes,
            varieties: ["Chickpea", "Lentil", "Dry Pea", "Dry Bean", "Broad Bean", "Lupin", other],
            colorHex: "6E8B3D",
            aliases: ["Leguminosas", "Leguminosas grano"]
        ),
        ProductionTypeItem(
            name: industrialCrops,
            varieties: ["Sunflower", "Rapeseed", "Soybean", "Sugar Beet", "Cotton", "Tobacco", "Hops", "Hemp", other],
            colorHex: "8E6AD8",
            aliases: ["Cultivos industriales", "Oleaginosas", "Industriales"]
        ),
        ProductionTypeItem(
            name: forageCrops,
            varieties: ["Alfalfa", "Forage Corn", "Vetch", "Clover", "Ryegrass", "Fescue", "Forage Sorghum", other],
            colorHex: "5AAE62",
            aliases: ["Forrajes", "Forrajeras"]
        ),
        ProductionTypeItem(
            name: citrus,
            varieties: ["Navelina", "Lane Late", "Valencia Late", "Clemenules", "Oronules", "Okitsu", "Owari", "Nova", "Fino", "Verna", "Star Ruby", "Kumquat", other],
            colorHex: "F2994A",
            aliases: ["Citricos", "Orange", "Tangerines", "Mandarins", "Mandarin", "Lemon", "Lime", "Grapefruit"]
        ),
        ProductionTypeItem(
            name: stoneFruits,
            varieties: ["Peach", "Nectarine", "Flat Peach", "Apricot", "Plum", "Cherry", "Picota", other],
            colorHex: "F06F8A",
            aliases: ["Fruta de hueso", "Frutales de hueso"]
        ),
        ProductionTypeItem(
            name: pomeFruits,
            varieties: ["Apple", "Pear", "Quince", other],
            colorHex: "E4A93C",
            aliases: ["Fruta de pepita", "Frutales de pepita"]
        ),
        ProductionTypeItem(
            name: nuts,
            varieties: ["Almond", "Pistachio", "Walnut", "Hazelnut", "Chestnut", "Carob", other],
            colorHex: "A56B4F",
            aliases: ["Frutos secos", "Frutos de cascara", "Frutos de cáscara"]
        ),
        ProductionTypeItem(
            name: berries,
            varieties: ["Strawberry", "Blueberry", "Raspberry", "Blackberry", "Currant", other],
            colorHex: "C44C7A",
            aliases: ["Frutos rojos"]
        ),
        ProductionTypeItem(
            name: tropicalFruits,
            varieties: ["Avocado", "Mango", "Cherimoya", "Papaya", "Banana", other],
            colorHex: "27AE9B",
            aliases: ["Frutas tropicales", "Subtropicales"]
        ),
        ProductionTypeItem(
            name: otherFruitTrees,
            varieties: ["Persimmon", "Pomegranate", "Fig", "Kiwi", "Loquat", other],
            colorHex: "8F61D4",
            aliases: ["Otros frutales", "Frutales tradicionales", "Pomegranate"]
        ),
        ProductionTypeItem(
            name: vineyard,
            varieties: ["Tempranillo", "Airen", "Garnacha", "Garnacha Tintorera", "Verdejo", "Bobal", "Monastrell", "Syrah", "Macabeo", "Cabernet Sauvignon", "Chardonnay", "Sauvignon Blanc", other],
            colorHex: "7B4D9F",
            aliases: ["Viñedo", "Vinedo", "Vitivinicultura", "Grapes", "Table Grapes"]
        ),
        ProductionTypeItem(
            name: oliveGrove,
            varieties: ["Picual", "Arbequina", "Hojiblanca", "Cornicabra", "Empeltre", "Lechin", "Manzanilla", "Gordal Sevillana", "Manzanilla Cacereña", "Carrasqueña", other],
            colorHex: "4B8F3A",
            aliases: ["Olivar", "Olives", "Olivo", "Olivos", "Aceituna", "Aceitunas"]
        ),
        ProductionTypeItem(
            name: flowersAndOrnamentals,
            varieties: ["Carnation", "Rose", "Chrysanthemum", "Gerbera", "Lily", "Hydrangea", other],
            colorHex: "E87CB4",
            aliases: ["Flores y ornamentales", "Flor y planta viva"]
        )
    ]

    static func item(for name: String) -> ProductionTypeItem? {
        let normalized = normalizeCatalogKey(name)
        guard !normalized.isEmpty else { return nil }

        return items.first { item in
            normalizeCatalogKey(item.name) == normalized ||
            item.aliases.contains(where: { normalizeCatalogKey($0) == normalized }) ||
            item.varieties.contains(where: { normalizeCatalogKey($0) == normalized })
        }
    }

    static func displayName(for name: String, language: AppLanguage) -> String {
        guard let item = item(for: name) else {
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? language.localized("Unspecified", "Sin definir")
                : name
        }

        switch item.name {
        case vegetables:
            return language.localized("Vegetables", "Hortalizas")
        case melonsAndWatermelons:
            return language.localized("Melons and Watermelons", "Melón y sandía")
        case cereals:
            return language.localized("Cereals", "Cereales")
        case legumes:
            return language.localized("Legumes", "Leguminosas")
        case industrialCrops:
            return language.localized("Industrial and Oil Crops", "Cultivos industriales y oleaginosos")
        case forageCrops:
            return language.localized("Forage Crops", "Forrajeras")
        case citrus:
            return language.localized("Citrus", "Cítricos")
        case stoneFruits:
            return language.localized("Stone Fruits", "Frutales de hueso")
        case pomeFruits:
            return language.localized("Pome Fruits", "Frutales de pepita")
        case nuts:
            return language.localized("Nuts", "Frutos secos")
        case berries:
            return language.localized("Berries", "Frutos rojos")
        case tropicalFruits:
            return language.localized("Tropical Fruits", "Frutas tropicales")
        case otherFruitTrees:
            return language.localized("Other Fruit Trees", "Otros frutales")
        case vineyard:
            return language.localized("Vineyard", "Viñedo")
        case oliveGrove:
            return language.localized("Olive Grove", "Olivar")
        case flowersAndOrnamentals:
            return language.localized("Flowers and Ornamentals", "Flores y ornamentales")
        default:
            return item.name
        }
    }

    static func displayVarietyName(for name: String, language: AppLanguage) -> String {
        switch normalizeCatalogKey(name) {
        case normalizeCatalogKey(other):
            return language.localized("Other", "Otra")
        case normalizeCatalogKey("Tomato"):
            return language.localized("Tomato", "Tomate")
        case normalizeCatalogKey("Cherry Tomato"):
            return language.localized("Cherry Tomato", "Tomate cherry")
        case normalizeCatalogKey("Pepper"):
            return language.localized("Pepper", "Pimiento")
        case normalizeCatalogKey("Eggplant"):
            return language.localized("Eggplant", "Berenjena")
        case normalizeCatalogKey("Cucumber"):
            return language.localized("Cucumber", "Pepino")
        case normalizeCatalogKey("Zucchini"):
            return language.localized("Zucchini", "Calabacín")
        case normalizeCatalogKey("Pumpkin"):
            return language.localized("Pumpkin", "Calabaza")
        case normalizeCatalogKey("Lettuce"):
            return language.localized("Lettuce", "Lechuga")
        case normalizeCatalogKey("Spinach"):
            return language.localized("Spinach", "Espinaca")
        case normalizeCatalogKey("Chard"):
            return language.localized("Chard", "Acelga")
        case normalizeCatalogKey("Celery"):
            return language.localized("Celery", "Apio")
        case normalizeCatalogKey("Endive"):
            return language.localized("Endive", "Escarola")
        case normalizeCatalogKey("Broccoli"):
            return language.localized("Broccoli", "Brócoli")
        case normalizeCatalogKey("Cauliflower"):
            return language.localized("Cauliflower", "Coliflor")
        case normalizeCatalogKey("Cabbage"):
            return language.localized("Cabbage", "Repollo")
        case normalizeCatalogKey("Artichoke"):
            return language.localized("Artichoke", "Alcachofa")
        case normalizeCatalogKey("Asparagus"):
            return language.localized("Asparagus", "Espárrago")
        case normalizeCatalogKey("Onion"):
            return language.localized("Onion", "Cebolla")
        case normalizeCatalogKey("Garlic"):
            return language.localized("Garlic", "Ajo")
        case normalizeCatalogKey("Leek"):
            return language.localized("Leek", "Puerro")
        case normalizeCatalogKey("Carrot"):
            return language.localized("Carrot", "Zanahoria")
        case normalizeCatalogKey("Turnip"):
            return language.localized("Turnip", "Nabo")
        case normalizeCatalogKey("Green Bean"):
            return language.localized("Green Bean", "Judía verde")
        case normalizeCatalogKey("Green Pea"):
            return language.localized("Green Pea", "Guisante verde")
        case normalizeCatalogKey("Mushroom"):
            return language.localized("Mushroom", "Champiñón")
        case normalizeCatalogKey("Melon"):
            return language.localized("Melon", "Melón")
        case normalizeCatalogKey("Watermelon"):
            return language.localized("Watermelon", "Sandía")
        case normalizeCatalogKey("Soft Wheat"):
            return language.localized("Soft Wheat", "Trigo blando")
        case normalizeCatalogKey("Durum Wheat"):
            return language.localized("Durum Wheat", "Trigo duro")
        case normalizeCatalogKey("Barley"):
            return language.localized("Barley", "Cebada")
        case normalizeCatalogKey("Oats"):
            return language.localized("Oats", "Avena")
        case normalizeCatalogKey("Rye"):
            return language.localized("Rye", "Centeno")
        case normalizeCatalogKey("Corn"):
            return language.localized("Corn", "Maíz")
        case normalizeCatalogKey("Rice"):
            return language.localized("Rice", "Arroz")
        case normalizeCatalogKey("Triticale"):
            return "Triticale"
        case normalizeCatalogKey("Sorghum"):
            return language.localized("Sorghum", "Sorgo")
        case normalizeCatalogKey("Chickpea"):
            return language.localized("Chickpea", "Garbanzo")
        case normalizeCatalogKey("Lentil"):
            return language.localized("Lentil", "Lenteja")
        case normalizeCatalogKey("Dry Pea"):
            return language.localized("Dry Pea", "Guisante seco")
        case normalizeCatalogKey("Dry Bean"):
            return language.localized("Dry Bean", "Judía seca")
        case normalizeCatalogKey("Broad Bean"):
            return language.localized("Broad Bean", "Haba")
        case normalizeCatalogKey("Lupin"):
            return language.localized("Lupin", "Altramuz")
        case normalizeCatalogKey("Sunflower"):
            return language.localized("Sunflower", "Girasol")
        case normalizeCatalogKey("Rapeseed"):
            return language.localized("Rapeseed", "Colza")
        case normalizeCatalogKey("Soybean"):
            return language.localized("Soybean", "Soja")
        case normalizeCatalogKey("Sugar Beet"):
            return language.localized("Sugar Beet", "Remolacha azucarera")
        case normalizeCatalogKey("Cotton"):
            return language.localized("Cotton", "Algodón")
        case normalizeCatalogKey("Tobacco"):
            return language.localized("Tobacco", "Tabaco")
        case normalizeCatalogKey("Hops"):
            return language.localized("Hops", "Lúpulo")
        case normalizeCatalogKey("Hemp"):
            return language.localized("Hemp", "Cáñamo")
        case normalizeCatalogKey("Alfalfa"):
            return "Alfalfa"
        case normalizeCatalogKey("Forage Corn"):
            return language.localized("Forage Corn", "Maíz forrajero")
        case normalizeCatalogKey("Vetch"):
            return language.localized("Vetch", "Veza")
        case normalizeCatalogKey("Clover"):
            return language.localized("Clover", "Trébol")
        case normalizeCatalogKey("Ryegrass"):
            return "Ray-grass"
        case normalizeCatalogKey("Fescue"):
            return language.localized("Fescue", "Festuca")
        case normalizeCatalogKey("Forage Sorghum"):
            return language.localized("Forage Sorghum", "Sorgo forrajero")
        case normalizeCatalogKey("Valencia Late"):
            return "Valencia Late"
        case normalizeCatalogKey("Clemenules"):
            return "Clemenules"
        case normalizeCatalogKey("Oronules"):
            return "Oronules"
        case normalizeCatalogKey("Okitsu"):
            return "Okitsu"
        case normalizeCatalogKey("Owari"):
            return "Owari"
        case normalizeCatalogKey("Nova"):
            return "Nova"
        case normalizeCatalogKey("Fino"):
            return "Fino"
        case normalizeCatalogKey("Verna"):
            return "Verna"
        case normalizeCatalogKey("Star Ruby"):
            return "Star Ruby"
        case normalizeCatalogKey("Kumquat"):
            return "Kumquat"
        case normalizeCatalogKey("Blood"):
            return language.localized("Blood Orange", "Sanguina")
        case normalizeCatalogKey("Mandarin"):
            return language.localized("Mandarin", "Mandarina")
        case normalizeCatalogKey("Clementine"):
            return language.localized("Clementine", "Clementina")
        case normalizeCatalogKey("Peach"):
            return language.localized("Peach", "Melocotón")
        case normalizeCatalogKey("Nectarine"):
            return language.localized("Nectarine", "Nectarina")
        case normalizeCatalogKey("Flat Peach"):
            return language.localized("Flat Peach", "Paraguayo")
        case normalizeCatalogKey("Apricot"):
            return language.localized("Apricot", "Albaricoque")
        case normalizeCatalogKey("Plum"):
            return language.localized("Plum", "Ciruela")
        case normalizeCatalogKey("Cherry"):
            return language.localized("Cherry", "Cereza")
        case normalizeCatalogKey("Picota"):
            return "Picota"
        case normalizeCatalogKey("Apple"):
            return language.localized("Apple", "Manzana")
        case normalizeCatalogKey("Pear"):
            return language.localized("Pear", "Pera")
        case normalizeCatalogKey("Quince"):
            return language.localized("Quince", "Membrillo")
        case normalizeCatalogKey("Almond"):
            return language.localized("Almond", "Almendra")
        case normalizeCatalogKey("Pistachio"):
            return language.localized("Pistachio", "Pistacho")
        case normalizeCatalogKey("Walnut"):
            return language.localized("Walnut", "Nogal")
        case normalizeCatalogKey("Hazelnut"):
            return language.localized("Hazelnut", "Avellana")
        case normalizeCatalogKey("Chestnut"):
            return language.localized("Chestnut", "Castaña")
        case normalizeCatalogKey("Carob"):
            return language.localized("Carob", "Algarroba")
        case normalizeCatalogKey("Strawberry"):
            return language.localized("Strawberry", "Fresa")
        case normalizeCatalogKey("Blueberry"):
            return language.localized("Blueberry", "Arándano")
        case normalizeCatalogKey("Raspberry"):
            return language.localized("Raspberry", "Frambuesa")
        case normalizeCatalogKey("Blackberry"):
            return language.localized("Blackberry", "Mora")
        case normalizeCatalogKey("Currant"):
            return language.localized("Currant", "Grosella")
        case normalizeCatalogKey("Avocado"):
            return language.localized("Avocado", "Aguacate")
        case normalizeCatalogKey("Mango"):
            return "Mango"
        case normalizeCatalogKey("Cherimoya"):
            return language.localized("Cherimoya", "Chirimoya")
        case normalizeCatalogKey("Papaya"):
            return "Papaya"
        case normalizeCatalogKey("Banana"):
            return language.localized("Banana", "Plátano")
        case normalizeCatalogKey("Persimmon"):
            return language.localized("Persimmon", "Caqui")
        case normalizeCatalogKey("Pomegranate"):
            return language.localized("Pomegranate", "Granada")
        case normalizeCatalogKey("Fig"):
            return language.localized("Fig", "Higo")
        case normalizeCatalogKey("Kiwi"):
            return "Kiwi"
        case normalizeCatalogKey("Loquat"):
            return language.localized("Loquat", "Níspero")
        case normalizeCatalogKey("Airen"):
            return "Airén"
        case normalizeCatalogKey("Garnacha"):
            return "Garnacha"
        case normalizeCatalogKey("Garnacha Tintorera"):
            return "Garnacha Tintorera"
        case normalizeCatalogKey("Verdejo"):
            return "Verdejo"
        case normalizeCatalogKey("Bobal"):
            return "Bobal"
        case normalizeCatalogKey("Monastrell"):
            return "Monastrell"
        case normalizeCatalogKey("Syrah"):
            return "Syrah"
        case normalizeCatalogKey("Macabeo"):
            return "Macabeo"
        case normalizeCatalogKey("Cabernet Sauvignon"):
            return "Cabernet Sauvignon"
        case normalizeCatalogKey("Chardonnay"):
            return "Chardonnay"
        case normalizeCatalogKey("Sauvignon Blanc"):
            return "Sauvignon Blanc"
        case normalizeCatalogKey("Picual"):
            return "Picual"
        case normalizeCatalogKey("Arbequina"):
            return "Arbequina"
        case normalizeCatalogKey("Hojiblanca"):
            return "Hojiblanca"
        case normalizeCatalogKey("Cornicabra"):
            return "Cornicabra"
        case normalizeCatalogKey("Empeltre"):
            return "Empeltre"
        case normalizeCatalogKey("Lechin"):
            return "Lechín"
        case normalizeCatalogKey("Manzanilla"):
            return "Manzanilla"
        case normalizeCatalogKey("Gordal Sevillana"):
            return "Gordal sevillana"
        case normalizeCatalogKey("Manzanilla Cacereña"):
            return "Manzanilla cacereña"
        case normalizeCatalogKey("Carrasqueña"):
            return "Carrasqueña"
        case normalizeCatalogKey("Carnation"):
            return language.localized("Carnation", "Clavel")
        case normalizeCatalogKey("Rose"):
            return language.localized("Rose", "Rosa")
        case normalizeCatalogKey("Chrysanthemum"):
            return language.localized("Chrysanthemum", "Crisantemo")
        case normalizeCatalogKey("Gerbera"):
            return "Gerbera"
        case normalizeCatalogKey("Lily"):
            return language.localized("Lily", "Lirio")
        case normalizeCatalogKey("Hydrangea"):
            return language.localized("Hydrangea", "Hortensia")
        case normalizeCatalogKey("Navel"):
            return "Navel"
        case normalizeCatalogKey("Valencia"):
            return "Valencia"
        case normalizeCatalogKey("Satsuma"):
            return "Satsuma"
        case normalizeCatalogKey("Wonderful"):
            return "Wonderful"
        case normalizeCatalogKey("Mollar"):
            return "Mollar"
        case normalizeCatalogKey("Eureka"):
            return "Eureka"
        case normalizeCatalogKey("Lisbon"):
            return "Lisbon"
        default:
            return name
        }
    }
}

private func normalizeCatalogKey(_ value: String) -> String {
    value
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

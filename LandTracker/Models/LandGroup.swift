import Foundation
import SwiftData

@Model
final class LandGroup {
    var id: UUID
    var name: String
    var colorHex: String
    @Relationship(inverse: \Land.group) var lands: [Land]
    var createdAt: Date

    init(name: String, colorHex: String, lands: [Land] = []) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.lands = lands
        self.createdAt = Date()
    }
}

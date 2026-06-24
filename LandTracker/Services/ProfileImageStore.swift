import Foundation
import Combine

final class ProfileImageStore: ObservableObject {
    static let shared = ProfileImageStore()

    @Published var imageData: Data?

    private init() {}
}

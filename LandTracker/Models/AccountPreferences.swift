import Foundation

enum AccountPreferences {
    static let displayNameKey = "account.displayName"
    static let accountTypeKey = "account.type"
    static let profilePhotoPathKey = "account.profilePhotoPath"
    static let cachedEmailKey = "account.cachedEmail"
    static let showIncomeInListKey = "account.showIncomeInList"
    static let showSubtypeInListKey = "account.showSubtypeInList"
    static let spreadsheetSourceFileNameKey = "data.spreadsheet.source.fileName"
    static let spreadsheetSourcePathKey = "data.spreadsheet.source.path"
    static let spreadsheetSourceHashKey = "data.spreadsheet.source.hash"
    static let spreadsheetSourceUpdatedAtKey = "data.spreadsheet.source.updatedAt"
    static let spreadsheetLastProcessedHashKey = "data.spreadsheet.lastProcessedHash"
    static let spreadsheetLastProcessedAtKey = "data.spreadsheet.lastProcessedAt"
    static let appLanguageKey = "settings.appLanguage"
    static let measurementSystemKey = "settings.measurementSystem"
    static let preferredCurrencyCodeKey = "settings.preferredCurrencyCode"
    static let pushDeviceTokenKey = "push.deviceToken"
    static let activeAccessRoleKey = "access.activeRole"
}

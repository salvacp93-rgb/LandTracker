# LandTracker — Project Guidelines

iOS app for land management. SwiftUI + SwiftData local-first, synced to Supabase. Built for agricultural/rural land owners and their teams.

---

## Architecture

```
LandTrackerApp (entry point)
├── AuthViewModel          — auth state, Supabase login/logout
├── RoleAccessViewModel    — active role, permissions
└── ContentView            — tab router (authenticated)
    ├── DashboardView
    ├── LandsView          — Lands tab: List/Map, one section per group + "Ungrouped" (logic in LandsHubViewModel)
    │   └── GroupDetailView / LandDetailView
    ├── InsightsView       — economic insights (owner-only)
    └── AccountView
```

**Layer rules (never violate):**
- `Views` call `Services` and `Models` — never the reverse
- `ViewModels` sit between `Views` and `Services`
- `Services` never import SwiftUI

---

## SwiftData Models

Registered in `LandTrackerApp.swift` — only these are in the schema:

| Model | File |
|-------|------|
| `Land` | `Models/Land.swift` |
| `LandGroup` | `Models/LandGroup.swift` |
| `LandHistoryEntry` | `Models/LandHistoryEntry.swift` |
| `LandTask` | `Models/LandTask.swift` |
| `PendingSyncOperation` | `Models/PendingSyncOperation.swift` |

`LandInsight`, `ProductionCatalog`, `AppSettings` are NOT SwiftData models — they are value types / computed.

To add a new model to persistence: add it to the `Schema` array in `LandTrackerApp.init()`.

---

## Role System

Two roles: `owner` and `employee` (defined in `AppAccessRole.swift`).

| Permission | Owner | Employee |
|-----------|-------|----------|
| `canViewEconomics` | ✅ | ❌ |
| `canManageStructure` | ✅ | ❌ |
| `canManageExpenses` | ✅ | ✅ |
| `canUseDailyOperations` | ✅ | ✅ |

**Active role is in `RoleAccessViewModel`** — injected as `@EnvironmentObject` everywhere.  
Always gate UI with `roleAccessViewModel.canViewEconomics` etc., never hardcode role strings.

`AppAccessRole.appRoles(from:)` maps Supabase org roles (`owner`, `admin`, `member`, `viewer`) → app roles. Default when unknown: `.owner`.

---

## Supabase Sync

- `SupabaseSyncService.shared` — main sync, queues upserts, fetches org roles
- `SupabaseAuthService` — login, logout, session management
- `SupabaseIoTService` — IoT device telemetry
- `PendingSyncOperation` — offline queue (SwiftData model)

On sign-out: `SupabaseSyncService.shared.clearLocalCache(context:)` + `roleAccessViewModel.resetForSignedOut()` — both must be called together (see `LandTrackerApp.swift:62`).

---

## Services Reference

| Service | Responsibility |
|---------|---------------|
| `SupabaseSyncService` | Land/group/task/history sync to cloud |
| `SupabaseAuthService` | Auth (email + Apple Sign In) |
| `SupabaseIoTService` | IoT telemetry push |
| `BluetoothPairingService` | BLE device discovery & pairing |
| `CatastroService` | Spanish Catastro parcel data fetch & parse |
| `ImportExportService` | JSON import/export of land data |
| `SpreadsheetImportService` | CSV spreadsheet import |
| `TaskReminderService` | Local push notification reminders |
| `PushNotificationService` | APNs device token sync |
| `ProfileImageStore` | In-memory profile image cache |

---

## Key Hotspots (high fan-in — touch carefully)

| Symbol | Fan-in | File |
|--------|--------|------|
| `AppLanguage.localized` | 57 | `Models/AppSettings.swift` |
| `GroupEditorView.save` | 24 | `Views/GroupEditorView.swift` |
| `LandHistoryEntry.touchUpdatedAt` | 12 | `Models/LandHistoryEntry.swift` |
| `SupabaseSyncService.queueLandUpsert` | 10 | `Services/SupabaseSyncService.swift` |

---

## i18n

All user-facing strings go through `AppLanguage.localized(_:_:)` — first arg is English, second is Spanish. Never hardcode display strings.

---

## What NOT to do

- Don't add new SwiftData models without adding them to the `Schema` in `LandTrackerApp.init()`
- Don't show economic data without checking `canViewEconomics`
- Don't call `clearLocalCache` without also calling `resetForSignedOut` (and vice versa)
- Don't call Supabase from a View directly — go through a Service
- Don't bypass `RoleAccessViewModel` to check roles — never compare role strings manually

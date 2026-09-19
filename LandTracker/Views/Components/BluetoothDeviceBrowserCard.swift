import SwiftUI

private enum BluetoothSignalFilter: String, CaseIterable, Identifiable {
    case nearby
    case closest
    case all

    var id: String { rawValue }

    var minimumRSSI: Int {
        switch self {
        case .nearby:
            return -70
        case .closest:
            return -55
        case .all:
            return Int.min
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .nearby:
            return language.localized("Nearby", "Cercanos")
        case .closest:
            return language.localized("Very close", "Muy cercanos")
        case .all:
            return language.localized("All", "Todos")
        }
    }
}

struct BluetoothDeviceBrowserCard: View {
    private let defaultVisibleResults = 6

    let language: AppLanguage
    @ObservedObject var pairingService: BluetoothPairingService

    @State private var searchText = ""
    @State private var signalFilter: BluetoothSignalFilter = .nearby
    @State private var showAllResults = false

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredDevices: [BluetoothScanDevice] {
        pairingService.discoveredDevices.filter { device in
            guard device.rssi >= signalFilter.minimumRSSI else { return false }
            guard !trimmedSearchText.isEmpty else { return true }

            return device.name.localizedCaseInsensitiveContains(trimmedSearchText) ||
                device.id.uuidString.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    private var visibleDevices: [BluetoothScanDevice] {
        if showAllResults {
            return filteredDevices
        }
        return Array(filteredDevices.prefix(defaultVisibleResults))
    }

    private var extraResultsCount: Int {
        max(0, filteredDevices.count - defaultVisibleResults)
    }

    private var hasResults: Bool {
        !pairingService.discoveredDevices.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                searchActionButton

                if pairingService.isScanning {
                    Text(language.localized("Scanning nearby devices", "Buscando dispositivos cercanos"))
                        .font(.poppins(.caption))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .lineLimit(1)
                } else if hasResults {
                    Text(language.localized("Search stopped", "Búsqueda detenida"))
                        .font(.poppins(.caption))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !pairingService.isBluetoothReady {
                Text(
                    language.localized(
                        "Enable Bluetooth on your iPhone to continue.",
                        "Activa Bluetooth en tu iPhone para continuar."
                    )
                )
                .font(.poppins(.caption))
                .foregroundStyle(AppTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let linked = pairingService.connectedDevice {
                Label(
                    language.localized("Linked with", "Enlazado con") + " \(linked.name)",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.poppins(.subheadline, .semibold))
                .foregroundStyle(AppTheme.positive)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            if pairingService.isConnecting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(language.localized("Connecting...", "Conectando..."))
                        .font(.poppins(.caption))
                        .foregroundStyle(AppTheme.inkSecondary)
                }
            }

            if let lastError = pairingService.lastError {
                Text(lastError)
                    .font(.poppins(.caption))
                    .foregroundStyle(AppTheme.negative)
            }

            if let sample = pairingService.latestSample {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        language.localized("Sample detected", "Muestra detectada") + ": \(sample.displayValue)",
                        systemImage: "waveform.path.ecg"
                    )
                    .font(.poppins(.subheadline, .semibold))
                    .foregroundStyle(AppTheme.olive)

                    Text(
                        language.localized(
                            "Live value detected from the device.",
                            "Se detectó un valor en vivo del dispositivo."
                        )
                    )
                    .font(.poppins(.caption))
                    .foregroundStyle(AppTheme.inkSecondary)
                }
                .padding(10)
                .background(AppTheme.olive.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if pairingService.connectedDevice != nil {
                Text(
                    language.localized(
                        "Connected. Waiting for a value sample...",
                        "Conectado. Esperando una muestra de valor..."
                    )
                )
                .font(.poppins(.caption))
                .foregroundStyle(AppTheme.inkSecondary)
            }

            if !pairingService.discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppTheme.inkSecondary)

                        TextField(
                            "",
                            text: $searchText,
                            prompt: Text(
                                language.localized(
                                    "Filter by name or device ID",
                                    "Filtrar por nombre o ID del dispositivo"
                                )
                            )
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 10) {
                            filterControl

                            Spacer(minLength: 12)

                            Text(resultsSummaryText)
                                .font(.poppins(.caption).monospacedDigit())
                                .foregroundStyle(AppTheme.inkSecondary)
                                .lineLimit(1)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            filterControl
                            Text(resultsSummaryText)
                                .font(.poppins(.caption).monospacedDigit())
                                .foregroundStyle(AppTheme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if pairingService.discoveredDevices.isEmpty {
                Text(
                    language.localized(
                        "No Bluetooth devices found yet. Keep the device in pairing mode and tap search.",
                        "Todavía no se encontraron dispositivos Bluetooth. Mantén el dispositivo en modo enlace y toca buscar."
                    )
                )
                .font(.poppins(.caption))
                .foregroundStyle(AppTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else if filteredDevices.isEmpty {
                Text(
                    language.localized(
                        "No devices match the current filters. Try another name or show all devices.",
                        "Ningún dispositivo coincide con los filtros actuales. Prueba otro nombre o muestra todos."
                    )
                )
                .font(.poppins(.caption))
                .foregroundStyle(AppTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(visibleDevices) { discovered in
                        BluetoothScanRow(
                            language: language,
                            device: discovered,
                            isLinked: pairingService.connectedDeviceID == discovered.id,
                            isBusy: pairingService.isConnecting && pairingService.connectedDeviceID != discovered.id,
                            onLink: {
                                pairingService.connect(to: discovered.id)
                            }
                        )
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                }

                if extraResultsCount > 0 {
                    Button {
                        showAllResults.toggle()
                    } label: {
                        Text(
                            showAllResults
                            ? language.localized("Show fewer results", "Mostrar menos resultados")
                            : language.localized(
                                "Show \(extraResultsCount) more results",
                                "Mostrar \(extraResultsCount) resultados más"
                            )
                        )
                        .font(.poppins(.caption, .semibold))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipped()
        .onChange(of: searchText) { _, _ in
            showAllResults = false
        }
        .onChange(of: signalFilter) { _, _ in
            showAllResults = false
        }
    }

    private var resultsSummaryText: String {
        let filteredCount = filteredDevices.count
        let totalCount = pairingService.discoveredDevices.count
        return language.localized(
            "\(filteredCount) of \(totalCount) devices",
            "\(filteredCount) de \(totalCount) dispositivos"
        )
    }

    private var filterControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.localized("Distance filter", "Filtro de distancia"))
                .font(.poppins(.caption, .semibold))
                .foregroundStyle(AppTheme.inkSecondary)

            Picker(
                language.localized("Distance filter", "Filtro de distancia"),
                selection: $signalFilter
            ) {
                ForEach(BluetoothSignalFilter.allCases) { filter in
                    Text(filter.title(language: language))
                        .tag(filter)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var searchActionButton: some View {
        let button = Button {
            if pairingService.isScanning {
                pairingService.stopScanning()
            } else {
                pairingService.startScanning()
            }
        } label: {
            if pairingService.isScanning {
                Image(systemName: "stop.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
            } else if hasResults {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
            } else {
                Label(
                    language.localized("Search nearby devices", "Buscar dispositivos cercanos"),
                    systemImage: "dot.radiowaves.left.and.right"
                )
            }
        }
        .disabled(!pairingService.isBluetoothReady)
        .accessibilityLabel(searchAccessibilityLabel)

        if pairingService.isScanning || !hasResults {
            button.buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.onBrand)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var searchAccessibilityLabel: String {
        if pairingService.isScanning {
            return language.localized("Stop search", "Detener búsqueda")
        }
        if hasResults {
            return language.localized("Search again", "Buscar de nuevo")
        }
        return language.localized("Search nearby devices", "Buscar dispositivos cercanos")
    }
}

private struct BluetoothScanRow: View {
    let language: AppLanguage
    let device: BluetoothScanDevice
    let isLinked: Bool
    let isBusy: Bool
    let onLink: () -> Void

    private var signalText: String {
        "\(device.rssi) dBm"
    }

    private var shortIdentifier: String {
        String(device.id.uuidString.prefix(8)).uppercased()
    }

    private var proximityLabel: String {
        if device.rssi >= -55 {
            return language.localized("Very close", "Muy cerca")
        }
        if device.rssi >= -70 {
            return language.localized("Nearby", "Cerca")
        }
        return language.localized("Weak signal", "Señal débil")
    }

    private var proximityTint: Color {
        if device.rssi >= -55 {
            return AppTheme.positive
        }
        if device.rssi >= -70 {
            return AppTheme.clay
        }
        return AppTheme.warning
    }

    /// Text version of `proximityTint`: the light amber and clay are too pale as small text.
    private var proximityTextTint: Color {
        if device.rssi >= -55 {
            return AppTheme.positive
        }
        if device.rssi >= -70 {
            return AppTheme.clayText
        }
        return AppTheme.warningText
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .foregroundStyle(isLinked ? AppTheme.positive : AppTheme.clay)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.poppins(.subheadline, .semibold))
                    .lineLimit(1)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        deviceMetaText
                        proximityBadge
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        deviceMetaText
                        proximityBadge
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button(isLinked ? language.localized("Linked", "Enlazado") : language.localized("Link", "Enlazar")) {
                onLink()
            }
            .foregroundStyle(AppTheme.onBrand)
            .buttonStyle(.borderedProminent)
            .disabled(isLinked || isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var deviceMetaText: some View {
        Text("\(signalText) | ID \(shortIdentifier)")
            .font(.poppins(.caption).monospacedDigit())
            .foregroundStyle(AppTheme.inkSecondary)
            .lineLimit(1)
    }

    private var proximityBadge: some View {
        Text(proximityLabel)
            .font(.poppins(.caption2, .semibold))
            .foregroundStyle(proximityTextTint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(proximityTint.opacity(0.12), in: Capsule())
    }
}

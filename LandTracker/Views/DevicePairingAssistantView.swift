import SwiftUI

struct DevicePairingAssistantView: View {
    let language: AppLanguage
    let measurementSystem: AppMeasurementSystem
    let onComplete: (LandDevice) -> Void

    @Environment(\.dismiss) private var dismiss

    @StateObject private var bluetoothPairingService = BluetoothPairingService()
    @State private var step: PairingAssistantStep = .welcome
    @State private var linkMethod: LandDeviceLinkMethod = .bluetooth
    @State private var deviceType: LandDeviceType = .thermometer
    @State private var deviceName = ""
    @State private var remoteConnectionConfirmed = false

    private var currentStepNumber: Int {
        step.rawValue + 1
    }

    private var totalSteps: Int {
        PairingAssistantStep.allCases.count
    }

    private var progressValue: Double {
        Double(currentStepNumber) / Double(totalSteps)
    }

    private var canMoveForward: Bool {
        switch step {
        case .welcome:
            return true
        case .method:
            return true
        case .prepare:
            switch linkMethod {
            case .manual:
                return true
            case .bluetooth:
                return bluetoothPairingService.connectedDevice != nil
            case .cloudAPI, .mqttGateway:
                return remoteConnectionConfirmed
            }
        case .details:
            return !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Group {
                switch step {
                case .welcome:
                    welcomeStep
                case .method:
                    methodStep
                case .prepare:
                    prepareStep
                case .details:
                    detailsStep
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            controls
        }
        .padding(16)
        .background(AppBackground())
        .navigationTitle(language.localized("Pair Device", "Enlazar dispositivo"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(language.localized("Cancel", "Cancelar")) {
                    dismiss()
                }
            }
        }
        .onChange(of: linkMethod) { _, newMethod in
            if newMethod != .bluetooth {
                bluetoothPairingService.stopScanning()
            }
            if newMethod != .cloudAPI && newMethod != .mqttGateway {
                remoteConnectionConfirmed = false
            }
        }
        .onChange(of: step) { _, newStep in
            if
                newStep == .prepare,
                linkMethod == .bluetooth,
                bluetoothPairingService.connectedDevice == nil,
                bluetoothPairingService.isBluetoothReady,
                !bluetoothPairingService.isScanning
            {
                bluetoothPairingService.startScanning()
            }
        }
        .onDisappear {
            bluetoothPairingService.stopScanning()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.localized("Quick setup assistant", "Asistente de configuración rápida"))
                    .font(.poppins(.headline))
                Spacer()
                Text(
                    language.localized("Step", "Paso") +
                    " \(currentStepNumber)/\(totalSteps)"
                )
                .font(.poppins(.caption, .semibold))
                .foregroundStyle(AppTheme.inkSecondary)
            }

            ProgressView(value: progressValue)
                .tint(AppTheme.olive)
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.oliveFill,
                                AppTheme.oliveDeepFill
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(spacing: 10) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                    Text(language.localized("We will guide you in 2 minutes.", "Te guiaremos en 2 minutos."))
                        .font(.poppins(.subheadline, .semibold))
                        .foregroundStyle(.white)
                }
                .padding(16)
            }
            .frame(height: 170)

            Text(
                language.localized(
                    "No technical knowledge needed. Follow the steps and we will create the device for you.",
                    "No necesitas conocimientos técnicos. Sigue los pasos y crearemos el dispositivo por ti."
                )
            )
            .font(.poppins(.subheadline))
            .foregroundStyle(AppTheme.inkSecondary)

            assistantHint(
                icon: "lightbulb.fill",
                text: language.localized(
                    "If you are next to the device, choose Bluetooth in the next step.",
                    "Si estás al lado del dispositivo, elige Bluetooth en el siguiente paso."
                )
            )
        }
    }

    private var methodStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.localized("How does this device send data?", "¿Cómo envía datos este dispositivo?"))
                .font(.poppins(.headline))

            MethodCard(
                isSelected: linkMethod == .bluetooth,
                icon: "dot.radiowaves.left.and.right",
                title: language.localized("Bluetooth nearby", "Bluetooth cercano"),
                subtitle: language.localized(
                    "Recommended when you are physically at the farm.",
                    "Recomendado si estás físicamente en la finca."
                )
            ) {
                linkMethod = .bluetooth
            }

            MethodCard(
                isSelected: linkMethod == .cloudAPI,
                icon: "cloud.fill",
                title: language.localized("Internet device", "Dispositivo con internet"),
                subtitle: language.localized(
                    "The device sends data from its own cloud or SIM/Wi-Fi.",
                    "El dispositivo envía datos desde su nube o SIM/Wi-Fi."
                )
            ) {
                linkMethod = .cloudAPI
            }

            MethodCard(
                isSelected: linkMethod == .mqttGateway,
                icon: "antenna.radiowaves.left.and.right",
                title: language.localized("Gateway", "Pasarela"),
                subtitle: language.localized(
                    "Sensor -> gateway -> app.",
                    "Sensor -> pasarela -> app."
                )
            ) {
                linkMethod = .mqttGateway
            }

            MethodCard(
                isSelected: linkMethod == .manual,
                icon: "hand.tap.fill",
                title: language.localized("Manual for now", "Manual por ahora"),
                subtitle: language.localized(
                    "Create device first and link physically later.",
                    "Crear dispositivo primero y enlazar físicamente después."
                )
            ) {
                linkMethod = .manual
            }
        }
    }

    private var prepareStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.localized("Preparation", "Preparación"))
                .font(.poppins(.headline))

            Text(preparationDescription)
                .font(.poppins(.subheadline))
                .foregroundStyle(AppTheme.inkSecondary)

            if linkMethod == .manual {
                assistantHint(
                    icon: "checkmark.seal.fill",
                    text: language.localized(
                        "You can continue now. We will save the device and you can link it later.",
                        "Puedes continuar ahora. Guardaremos el dispositivo y podrás enlazarlo más tarde."
                    )
                )
            } else if linkMethod == .bluetooth {
                BluetoothDeviceBrowserCard(
                    language: language,
                    pairingService: bluetoothPairingService
                )
            } else {
                VStack(spacing: 10) {
                    Toggle(
                        language.localized("I confirmed this device is online", "Confirmo que este dispositivo está en línea"),
                        isOn: $remoteConnectionConfirmed
                    )
                    .toggleStyle(.switch)
                    .tint(AppTheme.olive)
                    .font(.poppins(.body))
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.localized("Final details", "Detalles finales"))
                .font(.poppins(.headline))

            PairingField(
                label: language.localized("What name should we use?", "¿Qué nombre quieres usar?"),
                placeholder: language.localized("Example: Main greenhouse sensor", "Ejemplo: Sensor principal del invernadero"),
                text: $deviceName
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(language.localized("Device type", "Tipo de dispositivo"))
                    .font(.poppins(.caption, .semibold))
                    .foregroundStyle(AppTheme.inkSecondary)
                Picker(language.localized("Device type", "Tipo de dispositivo"), selection: $deviceType) {
                    ForEach(LandDeviceType.allCases) { type in
                        Label(type.displayName(language: language), systemImage: type.symbolName)
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if step != .welcome {
                Button(language.localized("Back", "Atrás")) {
                    previousStep()
                }
                .font(.poppins(.body, .medium))
                .buttonStyle(.bordered)
            }

            Spacer()

            Button(step == .details ? language.localized("Finish", "Finalizar") : language.localized("Continue", "Continuar")) {
                if step == .details {
                    completeAssistant()
                } else {
                    nextStep()
                }
            }
            .font(.poppins(.body, .semibold))
            .foregroundStyle(AppTheme.onBrand)
            .buttonStyle(.borderedProminent)
            .disabled(!canMoveForward)
        }
    }

    private var preparationDescription: String {
        switch linkMethod {
        case .bluetooth:
            return language.localized(
                "Turn on the device and activate pairing mode (usually by pressing the side button for 3-5 seconds).",
                "Enciende el dispositivo y activa el modo de enlace (normalmente pulsando el botón lateral durante 3-5 segundos)."
            )
        case .cloudAPI:
            return language.localized(
                "Make sure the device has internet and appears online in its manufacturer app.",
                "Asegúrate de que el dispositivo tiene internet y aparece en línea en su app del fabricante."
            )
        case .mqttGateway:
            return language.localized(
                "Make sure the sensor is close to its gateway and both are powered on.",
                "Asegúrate de que el sensor esté cerca de su pasarela y ambos encendidos."
            )
        case .manual:
            return language.localized(
                "No physical linking now. We will save the device and you can complete real linking later.",
                "No habrá enlace físico ahora. Guardaremos el dispositivo y podrás completar el enlace real más tarde."
            )
        }
    }

    private func nextStep() {
        guard let next = PairingAssistantStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func previousStep() {
        guard let previous = PairingAssistantStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func completeAssistant() {
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if linkMethod == .bluetooth, bluetoothPairingService.connectedDevice == nil {
            return
        }

        let metric = metricDefaults(for: deviceType)
        let intervalMinutes = 5
        let intervalSeconds = IoTDeviceLinkService.shared.normalizedIntervalSeconds(
            requestedMinutes: intervalMinutes,
            method: linkMethod
        )
        let linkedBluetoothDevice = bluetoothPairingService.connectedDevice
        let latestSample = bluetoothPairingService.latestSample

        let device = LandDevice(
            name: trimmedName,
            type: deviceType,
            manufacturer: manufacturerTitle(for: linkMethod),
            model: linkMethod == .bluetooth ? (linkedBluetoothDevice?.name ?? "") : "",
            serialNumber: linkMethod == .bluetooth ? (linkedBluetoothDevice?.id.uuidString ?? "") : "",
            metricName: metric.name,
            metricUnit: metric.unit,
            lastReadingValue: latestSample?.valueDouble,
            batteryLevel: nil,
            installedAt: Date(),
            lastSeenAt: latestSample?.observedAt,
            isActive: true,
            notes: noteText(for: linkMethod, sample: latestSample),
            linkMethod: linkMethod,
            linkState: linkMethod == .manual ? .unlinked : .linked,
            telemetryIntervalSeconds: intervalSeconds
        )

        onComplete(device)
        dismiss()
    }

    private func manufacturerTitle(for method: LandDeviceLinkMethod) -> String {
        switch method {
        case .bluetooth:
            return "Bluetooth"
        case .cloudAPI:
            return "Cloud API"
        case .mqttGateway:
            return "MQTT Gateway"
        case .manual:
            return "Manual"
        }
    }

    private func noteText(for method: LandDeviceLinkMethod, sample: BluetoothDataSample?) -> String {
        switch method {
        case .bluetooth:
            if
                let linkedName = bluetoothPairingService.connectedDevice?.name,
                let sample {
                return language.localized(
                    "Linked from assistant using Bluetooth (\(linkedName)). Initial sample: \(sample.displayValue).",
                    "Enlazado desde el asistente por Bluetooth (\(linkedName)). Muestra inicial: \(sample.displayValue)."
                )
            }
            if let linkedName = bluetoothPairingService.connectedDevice?.name {
                return language.localized(
                    "Linked from assistant using Bluetooth (\(linkedName)).",
                    "Enlazado desde el asistente por Bluetooth (\(linkedName))."
                )
            }
            return language.localized("Linked from assistant using Bluetooth.", "Enlazado desde el asistente por Bluetooth.")
        case .cloudAPI:
            return language.localized("Configured for cloud ingestion.", "Configurado para ingesta en la nube.")
        case .mqttGateway:
            return language.localized("Configured for gateway ingestion.", "Configurado para ingesta por pasarela.")
        case .manual:
            return language.localized("Created from assistant. Pending physical link.", "Creado desde el asistente. Pendiente de enlace físico.")
        }
    }

    private func metricDefaults(for type: LandDeviceType) -> (name: String, unit: String) {
        switch type {
        case .thermometer:
            return (
                language.localized("Temperature", "Temperatura"),
                measurementSystem == .imperial ? "F" : "C"
            )
        case .waterPump:
            return (
                language.localized("Flow", "Caudal"),
                measurementSystem == .imperial ? "gal/min" : "L/min"
            )
        case .rainGauge:
            return (
                language.localized("Rain", "Lluvia"),
                measurementSystem == .imperial ? "in" : "mm"
            )
        case .humiditySensor:
            return (language.localized("Humidity", "Humedad"), "%")
        case .pressureSensor:
            return (
                language.localized("Pressure", "Presión"),
                measurementSystem == .imperial ? "psi" : "hPa"
            )
        case .energyMeter:
            return (language.localized("Energy", "Energía"), "kWh")
        case .inverter:
            return (language.localized("Power", "Potencia"), "kW")
        case .other:
            return (language.localized("Value", "Valor"), "")
        }
    }

    @ViewBuilder
    private func assistantHint(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.olive)
                .padding(.top, 2)
            Text(text)
                .font(.poppins(.subheadline))
                .foregroundStyle(AppTheme.inkSecondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private enum PairingAssistantStep: Int, CaseIterable {
    case welcome
    case method
    case prepare
    case details
}

private struct MethodCard: View {
    let isSelected: Bool
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(isSelected ? AppTheme.olive : AppTheme.inkSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.poppins(.subheadline, .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.poppins(.caption))
                        .foregroundStyle(AppTheme.inkSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.olive : AppTheme.inkSecondary)
            }
            .padding(12)
            .background(
                isSelected ? AppTheme.olive.opacity(0.12) : AppTheme.card,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppTheme.olive.opacity(0.35) : AppTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PairingField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    private var isFilled: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.poppins(.caption, .semibold))
                .foregroundStyle(AppTheme.inkSecondary)

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .font(.poppins(.body))
                if isFilled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.positive)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
    }
}

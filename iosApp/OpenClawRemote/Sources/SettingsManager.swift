import Foundation
import Combine

final class SettingsManager: ObservableObject {
    private let defaults = UserDefaults.standard
    private let _config = CurrentValueSubject<GatewayConfig, Never>(GatewayConfig())

    var config: GatewayConfig { _config.value }

    @Published var configPublished: GatewayConfig = GatewayConfig()

    var configFlow: AnyPublisher<GatewayConfig, Never> {
        _config.eraseToAnyPublisher()
    }

    init() {
        let loaded = Self.loadConfig(from: defaults)
        _config.send(loaded)
        configPublished = loaded
    }

    private static func loadConfig(from defaults: UserDefaults) -> GatewayConfig {
        GatewayConfig(
            gatewayUrl: defaults.string(forKey: "gateway_url") ?? "wss://boson-tech.top/ws",
            deviceId: defaults.string(forKey: "device_id") ?? "",
            deviceLabel: defaults.string(forKey: "device_label") ?? "",
            token: defaults.string(forKey: "token") ?? "",
            pairedBackendId: defaults.string(forKey: "paired_backend_id"),
            pairedBackendLabel: defaults.string(forKey: "paired_backend_label")
        )
    }

    private func saveConfig(_ config: GatewayConfig) {
        defaults.set(config.gatewayUrl, forKey: "gateway_url")
        defaults.set(config.deviceId, forKey: "device_id")
        defaults.set(config.deviceLabel, forKey: "device_label")
        defaults.set(config.token, forKey: "token")
        if let pairedId = config.pairedBackendId {
            defaults.set(pairedId, forKey: "paired_backend_id")
        } else {
            defaults.removeObject(forKey: "paired_backend_id")
        }
        if let pairedLabel = config.pairedBackendLabel {
            defaults.set(pairedLabel, forKey: "paired_backend_label")
        } else {
            defaults.removeObject(forKey: "paired_backend_label")
        }
        _config.send(config)
        configPublished = config
    }

    func updateConfig(_ config: GatewayConfig) {
        saveConfig(config)
    }

    func updateDeviceId(_ id: String) {
        var current = _config.value
        current.deviceId = id
        saveConfig(current)
    }

    func updateGatewayUrl(_ url: String) {
        var current = _config.value
        current.gatewayUrl = url
        saveConfig(current)
    }

    func updatePairedBackend(_ backendId: String?, _ backendLabel: String?) {
        var current = _config.value
        current.pairedBackendId = backendId
        current.pairedBackendLabel = backendLabel
        saveConfig(current)
    }
}
import Combine
import CoreBluetooth
import Foundation

enum HeadsetConnectionState: Equatable {
    case idle
    case scanning
    case connecting(String)
    case connected(String)
    case ready(String)
    case unsupportedProduct(UInt16)
    case bluetoothUnavailable(String)
}

enum HeadsetBLEEvent {
    case ready
    case disconnected
    case wake(side: HeadsetSide?, payload: Data)
    case sleep(payload: Data)
    case keySettingsAck(success: Bool, payload: Data)
    case voiceRecognitionAck(success: Bool, payload: Data)
    case opusRecordingAck(success: Bool, payload: Data)
    case keyConfiguration(payload: Data)
    case rawNotify(label: String, payload: Data)
    case audioChunk(side: HeadsetSide, opusData: Data, frameCount: Int, frameSize: Int)
    case error(String)
}

private enum A9UltraCandidateKind {
    case advertisesTargetService
    case nameOnlyProbe
    case rejected
}

private struct A9UltraControlChannel {
    let service: CBService
    let write: CBCharacteristic
    let notify: CBCharacteristic
    let priority: Int

    var label: String {
        "\(service.uuid.uuidString)/W:\(write.uuid.uuidString)/N:\(notify.uuid.uuidString)"
    }
}

struct A9UltraDebugInfo: Equatable {
    var productId: UInt16?
    var hasWriteCharacteristic = false
    var hasNotifyCharacteristic = false
    var lastFrameCommand: UInt8?
    var audioChunkCount = 0
    var lastError: String?

    var productIdText: String {
        productId.map { "0x\(String($0, radix: 16))" } ?? "-"
    }

    var lastFrameText: String {
        lastFrameCommand.map { "0x\(String($0, radix: 16))" } ?? "-"
    }
}

final class A9UltraBLEManager: NSObject, ObservableObject {
    static let targetProductId: UInt16 = A9UltraPrivateProtocolPolicy.targetProductId
    /// 调试开关：设为 true 可在 Xcode Console 看到所有 BLE Notify 原始数据
    private static let debugLoggingEnabled = true

    private let serviceUUID = CBUUID(string: "FF12")
    private let writeUUID = CBUUID(string: "FF15")
    private let notifyUUID = CBUUID(string: "FF14")
    private let observedControlServiceUUID = CBUUID(string: "FDB3")
    private let observedWriteUUID = CBUUID(string: "FF17")
    private let observedFallbackWriteUUID = CBUUID(string: "FF16")
    private let observedNotifyUUID = CBUUID(string: "FF18")
    private let deviceInfoServiceUUID = CBUUID(string: "180A")
    private let pnpIdCharacteristicUUID = CBUUID(string: "2A50")
    private let codec = ABMateFrameCodec()
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var fallbackScanWorkItem: DispatchWorkItem?
    private var hasStartedFallbackScan = false
    private var productVerified = false
    private var shouldDiscoverAllServices = false
    private var rejectedPeripheralIds = Set<UUID>()
    private var pendingCharacteristicServiceIds = Set<String>()
    private var discoveredProbeChannels: [A9UltraControlChannel] = []
    private var activeProbeChannel: A9UltraControlChannel?
    private var probeTimeoutWorkItem: DispatchWorkItem?
    private var awaitingDeviceProfileResponse = false

    let events = PassthroughSubject<HeadsetBLEEvent, Never>()

    @Published private(set) var state: HeadsetConnectionState = .idle
    @Published private(set) var productId: UInt16?
    @Published private(set) var lastError: String?
    @Published private(set) var debugInfo = A9UltraDebugInfo()
    @Published private(set) var debugLogLines: [String] = []

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "BosonRelay.A9Ultra"]
        )
    }

    func start() {
        appendDebugLog("start, central=\(central.state.debugLabel)")
        guard central.state == .poweredOn else { return }
        startScanning(serviceFiltered: true)
    }

    func stop() {
        appendDebugLog("stop")
        fallbackScanWorkItem?.cancel()
        probeTimeoutWorkItem?.cancel()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        central.stopScan()
        state = .idle
    }

    func restartScan() {
        appendDebugLog("restart scan")
        fallbackScanWorkItem?.cancel()
        probeTimeoutWorkItem?.cancel()
        hasStartedFallbackScan = false
        rejectedPeripheralIds.removeAll()
        disconnectCurrent()
        guard central.state == .poweredOn else {
            lastError = "蓝牙未就绪，无法重连"
            refreshDebugInfo()
            return
        }
        startScanning(serviceFiltered: true)
    }

    func retryHandshake() {
        appendDebugLog("retry handshake")
        guard let peripheral else {
            lastError = "未连接耳机，无法重试校验"
            appendDebugLog("retry failed: no peripheral")
            refreshDebugInfo()
            start()
            return
        }
        if let notifyCharacteristic {
            appendDebugLog("resubscribe notify \(notifyCharacteristic.uuid.uuidString)")
            peripheral.setNotifyValue(true, for: notifyCharacteristic)
        }
        if writeCharacteristic != nil, notifyCharacteristic != nil {
            appendDebugLog("retry device info")
            requestDeviceProfile()
            armProbeTimeout()
        } else {
            appendDebugLog("rediscover services, write=\(writeCharacteristic != nil), notify=\(notifyCharacteristic != nil)")
            peripheral.discoverServices(nil)
        }
        refreshDebugInfo()
    }

    func forceReadyForDebug() {
        guard writeCharacteristic != nil, notifyCharacteristic != nil else {
            lastError = "调试强制就绪失败：write/notify 未就绪"
            appendDebugLog("force ready blocked: write=\(writeCharacteristic != nil), notify=\(notifyCharacteristic != nil)")
            refreshDebugInfo()
            return
        }
        guard A9UltraPrivateProtocolPolicy.accepts(productId: productId) else {
            lastError = "调试强制就绪失败：PID 未通过"
            appendDebugLog("force ready blocked: pid=\(productId.map { String($0, radix: 16) } ?? "-")")
            refreshDebugInfo()
            return
        }
        appendDebugLog("force ready")
        configureVerifiedDevice()
    }

    func setOpusRecording(enabled: Bool) {
        guard productVerified else {
            appendDebugLog("opus recording \(enabled ? "on" : "off") skipped: PID not verified")
            return
        }
        appendDebugLog("opus recording \(enabled ? "on" : "off")")
        send(
            command: .opusRecording,
            payload: ABMateTLVCodec.encode([.init(type: 0x01, value: Data([enabled ? 0x01 : 0x00]))])
        )
    }

    private func startScanning(serviceFiltered: Bool) {
        fallbackScanWorkItem?.cancel()
        central.stopScan()
        state = .scanning
        let services = serviceFiltered ? [serviceUUID] : nil
        appendDebugLog("scan \(serviceFiltered ? "service FF12" : "all devices")")
        central.scanForPeripherals(withServices: services, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        if serviceFiltered && !hasStartedFallbackScan {
            let fallback = DispatchWorkItem { [weak self] in
                guard let self, self.peripheral == nil else { return }
                self.hasStartedFallbackScan = true
                self.appendDebugLog("fallback scan all devices")
                self.startScanning(serviceFiltered: false)
            }
            fallbackScanWorkItem = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: fallback)
        }
    }

    private func connect(_ candidate: CBPeripheral, discoverAllServices: Bool) {
        fallbackScanWorkItem?.cancel()
        probeTimeoutWorkItem?.cancel()
        central.stopScan()
        peripheral = candidate
        candidate.delegate = self
        shouldDiscoverAllServices = discoverAllServices
        clearControlChannel()
        appendDebugLog("connect \(candidate.name ?? "unknown") id=\(candidate.identifier.uuidString.prefix(8)) allServices=\(discoverAllServices)")
        state = .connecting(candidate.name ?? "A9Ultra")
        central.connect(candidate)
    }

    private func classifyCandidate(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> A9UltraCandidateKind {
        if rejectedPeripheralIds.contains(peripheral.identifier) {
            return .rejected
        }
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           uuids.contains(serviceUUID) {
            return .advertisesTargetService
        }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let isNameMatch = name.localizedCaseInsensitiveContains("A9")
            || name.localizedCaseInsensitiveContains("Ultra")
            || name.localizedCaseInsensitiveContains("A9Ultra")
        return isNameMatch ? .nameOnlyProbe : .rejected
    }

    private func requestDeviceProfile() {
        appendDebugLog("request device profile")
        awaitingDeviceProfileResponse = true
        send(command: .deviceInfo, payload: A9UltraPrivateProtocolPolicy.deviceInfoRequestPayload)
    }

    private func configureVerifiedDevice() {
        guard A9UltraPrivateProtocolPolicy.accepts(productId: productId) else {
            failPrivateProtocolVerification("PID 未通过，拒绝配置 A9 私有链路")
            return
        }
        appendDebugLog("configure verified device")
        probeTimeoutWorkItem?.cancel()
        awaitingDeviceProfileResponse = false
        lastError = nil
        productVerified = true
        send(command: .voiceRecognition, payload: A9UltraPrivateProtocolPolicy.voiceRecognitionEnablePayload)
        appendDebugLog("voice recognition ON sent")
        let keyPayload = A9UltraKeyConfiguration.voiceAssistantCommandPayload
        appendDebugLog("key config payload=\(keyPayload.hexPrefix(24))")
        send(command: .keySettings, payload: keyPayload)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.requestKeyConfigurationReadback()
        }
        events.send(.ready)
        if case .connected(let name) = state {
            state = .ready(name)
        }
        refreshDebugInfo()
    }

    private func requestKeyConfigurationReadback() {
        appendDebugLog("request key config readback")
        let payload = ABMateTLVCodec.encode([ABMateTLVCodec.empty(0x05)])
        send(command: .deviceInfo, payload: payload)
    }

    private func send(command: ABMateCommand, payload: Data = Data()) {
        guard let peripheral, let writeCharacteristic else {
            appendDebugLog("send \(command.debugName) skipped: write not ready")
            return
        }
        let frames = codec.makeRequest(command: command, payload: payload)
        appendDebugLog("send \(command.debugName), frames=\(frames.count), payload=\(payload.count)")
        let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        for frame in frames {
            peripheral.writeValue(frame, for: writeCharacteristic, type: writeType)
        }
    }

    private func handleIncoming(_ data: Data) {
        appendDebugLog("notify data len=\(data.count) head=\(data.hexPrefix(8))")
        for frame in codec.parse(data) {
            debugInfo.lastFrameCommand = frame.command
            appendDebugLog("frame cmd=0x\(String(frame.command, radix: 16)) type=\(frame.type.rawValue) payload=\(frame.payload.count)")
            switch frame.command {
            case ABMateCommand.keySettings.rawValue:
                handleKeySettingsResponse(frame)
            case ABMateCommand.deviceInfo.rawValue, ABMateCommand.deviceInfoNotify.rawValue:
                handleDeviceInfo(frame)
            case ABMateCommand.voiceRecognition.rawValue:
                handleVoiceRecognitionResponse(frame)
            case ABMateCommand.opusRecording.rawValue:
                handleOpusRecordingResponse(frame)
            case ABMateCommand.recordingData.rawValue:
                handleRecordingData(frame.payload)
            default:
                events.send(.rawNotify(label: String(format: "cmd %02x", frame.command), payload: frame.payload))
                break
            }
        }
    }

    private func handleDeviceInfo(_ frame: ABMateFrame) {
        let tlvs = ABMateTLVCodec.parse(frame.payload)
        appendDebugLog("device info tlv=\(tlvs.map { "0x\(String($0.type, radix: 16))" }.joined(separator: ","))")
        var responseProductId: UInt16?
        var capabilities: UInt16?
        for item in tlvs {
            switch item.type {
            case 0x24:
                guard let productId = item.value.littleEndianUInt16(at: 0) else { continue }
                responseProductId = productId
                self.productId = productId
                debugInfo.productId = productId
                appendDebugLog("product id 0x\(String(productId, radix: 16))")
            case 0xFE:
                capabilities = item.value.littleEndianUInt16(at: 0)
                if let capabilities {
                    appendDebugLog("capabilities 0x\(String(capabilities, radix: 16))")
                }
            case 0xFF:
                if let maxLength = item.value.first {
                    codec.maxPacketLength = max(Int(maxLength), 20)
                    appendDebugLog("max packet \(codec.maxPacketLength)")
                }
            case 0x26:
                guard productVerified else {
                    appendDebugLog("ignore wake/sleep before PID verification payload=\(item.value.hexPrefix(8))")
                    break
                }
                guard let event = HeadsetWakeSleepEvent(value: item.value) else { break }
                switch event {
                case .wake(let side):
                    appendDebugLog("wake notify payload=\(item.value.hexPrefix(8))")
                    events.send(.wake(side: side, payload: item.value))
                case .sleep:
                    appendDebugLog("sleep notify payload=\(item.value.hexPrefix(8))")
                    events.send(.sleep(payload: item.value))
                }
            case 0x05:
                appendDebugLog("key config readback \(A9UltraKeyConfiguration.summary(item.value))")
                events.send(.keyConfiguration(payload: item.value))
            default:
                if frame.command == ABMateCommand.deviceInfoNotify.rawValue {
                    events.send(.rawNotify(label: String(format: "tlv %02x", item.type), payload: item.value))
                }
                break
            }
        }

        guard !productVerified,
              frame.command == ABMateCommand.deviceInfo.rawValue,
              frame.type == .response else {
            return
        }

        guard let responseProductId else {
            failPrivateProtocolVerification("设备信息未返回 PID，停止 A9 私有链路")
            return
        }

        guard A9UltraPrivateProtocolPolicy.accepts(productId: responseProductId) else {
            rejectUnsupportedProduct(responseProductId)
            return
        }

        if let capabilities,
           !A9UltraPrivateProtocolPolicy.supportsVoiceRecognition(capabilities: capabilities) {
            failPrivateProtocolVerification("A9 设备不支持语音识别能力 bit4，停止私有按键链路")
            return
        }

        configureVerifiedDevice()
    }

    private func handleKeySettingsResponse(_ frame: ABMateFrame) {
        let success = A9UltraKeyConfiguration.isSuccessfulAck(frame.payload)
        appendDebugLog("key settings ack \(success ? "ok" : "failed") payload=\(frame.payload.hexPrefix(24))")
        events.send(.keySettingsAck(success: success, payload: frame.payload))
    }

    private func handleVoiceRecognitionResponse(_ frame: ABMateFrame) {
        let success = frame.payload.first == 0x00
        appendDebugLog("voice recognition ack \(success ? "ok" : "failed") payload=\(frame.payload.hexPrefix(24))")
        events.send(.voiceRecognitionAck(success: success, payload: frame.payload))
    }

    private func handleOpusRecordingResponse(_ frame: ABMateFrame) {
        let tlvSuccess = A9UltraKeyConfiguration.isSuccessfulAck(frame.payload)
        let flatSuccess = frame.payload.first == 0x00
        let success = tlvSuccess || flatSuccess
        appendDebugLog("opus recording ack \(success ? "ok" : "failed") payload=\(frame.payload.hexPrefix(24))")
        events.send(.opusRecordingAck(success: success, payload: frame.payload))
    }

    private func handleRecordingData(_ payload: Data) {
        guard productVerified else {
            appendDebugLog("ignore audio before PID verification")
            return
        }
        guard let packet = HeadsetRecordingPacket.parse(payload) else { return }
        debugInfo.audioChunkCount += 1
        appendDebugLog("audio chunk \(debugInfo.audioChunkCount), side=\(packet.side.rawValue), opus=\(packet.opusData.count)")
        events.send(.audioChunk(side: packet.side, opusData: packet.opusData, frameCount: packet.frameCount, frameSize: packet.frameSize))
    }

    private func handlePnPId(_ data: Data) {
        guard data.count >= 7,
              let vendorId = data.littleEndianUInt16(at: 1),
              let productId = data.littleEndianUInt16(at: 3),
              let productVersion = data.littleEndianUInt16(at: 5) else {
            appendDebugLog("pnp id invalid \(data.hexPrefix(16))")
            return
        }
        appendDebugLog(
            "pnp id source=\(data[0]) vendor=0x\(String(vendorId, radix: 16)) product=0x\(String(productId, radix: 16)) version=0x\(String(productVersion, radix: 16))"
        )
        if productId == Self.targetProductId {
            self.productId = productId
            debugInfo.productId = productId
        }
        refreshDebugInfo()
    }

    private func rejectUnsupportedProduct(_ productId: UInt16) {
        state = .unsupportedProduct(productId)
        lastError = "检测到非 A9Ultra 设备: 0x\(String(productId, radix: 16))"
        debugInfo.lastError = lastError
        appendDebugLog("unsupported product 0x\(String(productId, radix: 16))")
        events.send(.error(lastError ?? "非 A9Ultra 设备"))
        disconnectCurrent()
    }

    private func failPrivateProtocolVerification(_ message: String) {
        lastError = message
        debugInfo.lastError = message
        appendDebugLog("private protocol verification failed: \(message)")
        events.send(.error(message))
        if let peripheral {
            rejectedPeripheralIds.insert(peripheral.identifier)
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func clearControlChannel() {
        writeCharacteristic = nil
        notifyCharacteristic = nil
        pendingCharacteristicServiceIds.removeAll()
        discoveredProbeChannels.removeAll()
        activeProbeChannel = nil
        awaitingDeviceProfileResponse = false
        probeTimeoutWorkItem?.cancel()
        probeTimeoutWorkItem = nil
    }

    private func disconnectCurrent() {
        appendDebugLog("disconnect current")
        probeTimeoutWorkItem?.cancel()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        clearControlChannel()
        productVerified = false
        shouldDiscoverAllServices = false
        refreshDebugInfo()
    }

    private func discoverAllCharacteristics(for services: [CBService], peripheral: CBPeripheral) {
        pendingCharacteristicServiceIds = Set(services.map { $0.uuid.uuidString })
        discoveredProbeChannels.removeAll()
        appendDebugLog("discover all chars, services=\(pendingCharacteristicServiceIds.count)")
        guard !services.isEmpty else {
            failControlChannelDiscovery("未发现 GATT 服务")
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    private func candidateChannels(in service: CBService, characteristics: [CBCharacteristic]) -> [A9UltraControlChannel] {
        var result: [A9UltraControlChannel] = []

        if let write = characteristics.first(where: { $0.uuid == writeUUID }),
           let notify = characteristics.first(where: { $0.uuid == notifyUUID }) {
            result.append(A9UltraControlChannel(service: service, write: write, notify: notify, priority: 0))
        }

        if service.uuid == observedControlServiceUUID,
           let notify = characteristics.first(where: { $0.uuid == observedNotifyUUID }) {
            if let write = characteristics.first(where: { $0.uuid == observedWriteUUID }) {
                result.append(A9UltraControlChannel(service: service, write: write, notify: notify, priority: 1))
            }
            if let write = characteristics.first(where: { $0.uuid == observedFallbackWriteUUID }) {
                result.append(A9UltraControlChannel(service: service, write: write, notify: notify, priority: 2))
            }
        }

        guard service.uuid.isLikelyVendorControlService else {
            return result
        }

        let writes = characteristics.filter {
            $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write)
        }
        let notifies = characteristics.filter {
            $0.properties.contains(.notify) || $0.properties.contains(.indicate)
        }
        let basePriority = service.uuid == serviceUUID ? 3 : service.uuid.uuidString.hasPrefix("FF") ? 10 : 20

        for write in writes {
            for notify in notifies {
                if service.uuid == serviceUUID, write.uuid == writeUUID, notify.uuid == notifyUUID {
                    continue
                }
                result.append(A9UltraControlChannel(service: service, write: write, notify: notify, priority: basePriority))
            }
        }

        return result
    }

    private func startBestControlChannelProbe() {
        guard !productVerified else { return }
        discoveredProbeChannels.sort {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.label < $1.label
        }
        var seen = Set<String>()
        discoveredProbeChannels = discoveredProbeChannels.filter { channel in
            seen.insert(channel.label).inserted
        }
        appendDebugLog("probe channels \(discoveredProbeChannels.map(\.label).joined(separator: " | "))")
        probeNextControlChannel()
    }

    private func probeNextControlChannel() {
        guard let peripheral else { return }
        probeTimeoutWorkItem?.cancel()
        awaitingDeviceProfileResponse = false

        guard !discoveredProbeChannels.isEmpty else {
            failControlChannelDiscovery("未找到可响应 AB Mate 的控制通道")
            return
        }

        let channel = discoveredProbeChannels.removeFirst()
        activeProbeChannel = channel
        writeCharacteristic = channel.write
        notifyCharacteristic = channel.notify
        appendDebugLog("probe channel \(channel.label)")
        refreshDebugInfo()

        if channel.notify.isNotifying {
            requestDeviceProfile()
            armProbeTimeout()
        } else {
            peripheral.setNotifyValue(true, for: channel.notify)
            armProbeTimeout()
        }
    }

    private func armProbeTimeout(seconds: TimeInterval = 1.6) {
        probeTimeoutWorkItem?.cancel()
        guard activeProbeChannel != nil, !productVerified else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.productVerified else { return }
            if let channel = self.activeProbeChannel {
                self.appendDebugLog("probe timeout \(channel.label)")
            }
            self.probeNextControlChannel()
        }
        probeTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    private func failControlChannelDiscovery(_ message: String) {
        lastError = "\(message)。如果日志里只有 1800/1801/180A/180F/1812 等标准服务，当前固件可能没有暴露 AB Mate BLE 控制通道。"
        debugInfo.lastError = lastError
        appendDebugLog("control channel failed: \(message)")
        events.send(.error(lastError ?? message))
        if let peripheral {
            rejectedPeripheralIds.insert(peripheral.identifier)
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func refreshDebugInfo() {
        debugInfo.productId = productId
        debugInfo.hasWriteCharacteristic = writeCharacteristic != nil
        debugInfo.hasNotifyCharacteristic = notifyCharacteristic != nil
        debugInfo.lastError = lastError
    }

    private func appendDebugLog(_ message: String) {
        guard Self.debugLoggingEnabled else { return }
        let line = message
        debugLogLines.append(line)
        if debugLogLines.count > 40 {
            debugLogLines.removeFirst(debugLogLines.count - 40)
        }
        print("[A9Ultra] \(line)")
    }
}

extension A9UltraBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        appendDebugLog("central state \(central.state.debugLabel)")
        switch central.state {
        case .poweredOn:
            start()
        case .poweredOff:
            state = .bluetoothUnavailable("蓝牙已关闭")
        case .unauthorized:
            state = .bluetoothUnavailable("蓝牙权限未开启")
        case .unsupported:
            state = .bluetoothUnavailable("当前设备不支持蓝牙")
        default:
            state = .bluetoothUnavailable("蓝牙暂不可用")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "unknown"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString).joined(separator: ",") ?? "-"
        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.hexPrefix(24) ?? "-"
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data])?
            .map { "\($0.key.uuidString)=\($0.value.hexPrefix(8))" }
            .sorted()
            .joined(separator: ",") ?? "-"
        guard self.peripheral == nil else { return }
        switch classifyCandidate(peripheral, advertisementData: advertisementData) {
        case .advertisesTargetService:
            appendDebugLog("discover target \(name), services=\(services), mfg=\(manufacturer), serviceData=\(serviceData)")
            connect(peripheral, discoverAllServices: false)
        case .nameOnlyProbe:
            appendDebugLog("discover name probe \(name), services=\(services), mfg=\(manufacturer), serviceData=\(serviceData)")
            connect(peripheral, discoverAllServices: true)
        case .rejected:
            return
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        appendDebugLog("did connect \(peripheral.name ?? "unknown")")
        state = .connected(peripheral.name ?? "A9Ultra")
        peripheral.discoverServices(shouldDiscoverAllServices ? nil : [serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lastError = error?.localizedDescription ?? "连接耳机失败"
        debugInfo.lastError = lastError
        appendDebugLog("connect failed \(lastError ?? "-")")
        state = .scanning
        startScanning(serviceFiltered: !hasStartedFallbackScan)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error {
            lastError = error.localizedDescription
            debugInfo.lastError = lastError
            appendDebugLog("did disconnect error \(error.localizedDescription)")
        } else {
            appendDebugLog("did disconnect")
        }
        events.send(.disconnected)
        disconnectCurrent()
        startScanning(serviceFiltered: !hasStartedFallbackScan)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restored = peripherals.first {
            appendDebugLog("restore peripheral \(restored.name ?? "unknown")")
            peripheral = restored
            restored.delegate = self
            central.connect(restored)
        }
    }
}

extension A9UltraBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lastError = error.localizedDescription
            debugInfo.lastError = lastError
            appendDebugLog("discover services error \(error.localizedDescription)")
            events.send(.error(error.localizedDescription))
            return
        }
        let services = peripheral.services ?? []
        appendDebugLog("services \(services.map(\.uuid.uuidString).joined(separator: ","))")
        if shouldDiscoverAllServices {
            discoverAllCharacteristics(for: services, peripheral: peripheral)
            return
        }
        if !services.contains(where: { $0.uuid == serviceUUID }) {
            appendDebugLog("FF12 service missing")
            rejectedPeripheralIds.insert(peripheral.identifier)
            shouldDiscoverAllServices = true
            peripheral.discoverServices(nil)
            return
        }
        for service in peripheral.services ?? [] where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            lastError = error.localizedDescription
            debugInfo.lastError = lastError
            appendDebugLog("discover characteristics error \(error.localizedDescription)")
            if shouldDiscoverAllServices {
                pendingCharacteristicServiceIds.remove(service.uuid.uuidString)
                if pendingCharacteristicServiceIds.isEmpty {
                    startBestControlChannelProbe()
                }
                return
            }
            events.send(.error(error.localizedDescription))
            return
        }
        let characteristics = service.characteristics ?? []
        appendDebugLog(
            "chars \(characteristics.map { "\($0.uuid.uuidString):\($0.properties.rawValue)" }.joined(separator: ","))"
        )

        if service.uuid == deviceInfoServiceUUID,
           let pnp = characteristics.first(where: { $0.uuid == pnpIdCharacteristicUUID }) {
            appendDebugLog("read pnp id")
            peripheral.readValue(for: pnp)
        }

        if shouldDiscoverAllServices {
            discoveredProbeChannels.append(contentsOf: candidateChannels(in: service, characteristics: characteristics))
            pendingCharacteristicServiceIds.remove(service.uuid.uuidString)
            if pendingCharacteristicServiceIds.isEmpty {
                startBestControlChannelProbe()
            }
        } else {
            discoveredProbeChannels = candidateChannels(in: service, characteristics: characteristics)
            if discoveredProbeChannels.isEmpty {
                failControlChannelDiscovery("FF12 服务缺少 FF15/FF14 特征")
            } else {
                startBestControlChannelProbe()
            }
        }
        refreshDebugInfo()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            lastError = error.localizedDescription
            debugInfo.lastError = lastError
            appendDebugLog("notify value error \(error.localizedDescription)")
            events.send(.error(error.localizedDescription))
            return
        }
        if characteristic.uuid == pnpIdCharacteristicUUID, let data = characteristic.value {
            handlePnPId(data)
            return
        }
        let isCurrentNotify = notifyCharacteristic.map { $0 === characteristic } ?? false
        guard (isCurrentNotify || characteristic.uuid == notifyUUID), let data = characteristic.value else { return }
        handleIncoming(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lastError = error.localizedDescription
            debugInfo.lastError = lastError
            appendDebugLog("notify state error \(error.localizedDescription)")
            return
        }
        appendDebugLog("notify state \(characteristic.uuid.uuidString)=\(characteristic.isNotifying)")
        let isCurrentNotify = notifyCharacteristic.map { $0 === characteristic } ?? false
        if isCurrentNotify, characteristic.isNotifying, !awaitingDeviceProfileResponse, !productVerified {
            requestDeviceProfile()
            armProbeTimeout()
        }
    }
}

private extension CBManagerState {
    var debugLabel: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknown-new"
        }
    }
}

private extension ABMateCommand {
    var debugName: String {
        "0x\(String(rawValue, radix: 16))"
    }
}

private extension Data {
    func hexPrefix(_ maxBytes: Int) -> String {
        prefix(maxBytes)
            .map { String(format: "%02x", $0) }
            .joined(separator: " ")
    }
}

private extension CBUUID {
    var isLikelyVendorControlService: Bool {
        let id = uuidString.uppercased()
        if id.count == 4, let value = UInt16(id, radix: 16) {
            return value >= 0xFD00
        }
        return id.count > 4
    }
}

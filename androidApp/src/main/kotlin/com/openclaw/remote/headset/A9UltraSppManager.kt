package com.openclaw.remote.headset

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.github.jaredmdobson.concentus.OpusDecoder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.util.UUID

sealed class A9UltraSppState {
    data object Idle : A9UltraSppState()
    data object Searching : A9UltraSppState()
    data class Connecting(val deviceName: String, val uuid: UUID) : A9UltraSppState()
    data class Verifying(val deviceName: String) : A9UltraSppState()
    data class Ready(val deviceName: String) : A9UltraSppState()
    data class Recording(val deviceName: String, val bytes: Int) : A9UltraSppState()
    data class Error(val message: String) : A9UltraSppState()

    val label: String
        get() = when (this) {
            Idle -> "耳机未启动"
            Searching -> "查找 A9 SPP"
            is Connecting -> "连接 ${deviceName} SPP"
            is Verifying -> "校验 ${deviceName}"
            is Ready -> "${deviceName} 就绪"
            is Recording -> "${deviceName} 录音中 ${bytes}B"
            is Error -> message
        }
}

class A9UltraSppManager(
    private val context: Context,
    private val onAudioReady: (ByteArray) -> Unit,
    private val onWake: () -> Unit = {},
    private val maxRecordingMs: Long = 300_000L,
    private val promptTonePlayer: HeadsetPromptTonePlayer = HeadsetPromptTonePlayer(),
    private val observeCommand: (ABMateSppCommand, ByteArray) -> Unit = { _, _ -> },
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val frameCodec = ABMateSppFrameCodec()
    private val packetParser = ABMateSppPacketParser()
    private val opusDecoder = A9UltraOpusDecoder()
    private val opusRecoveryGate = A9UltraOpusRecoveryGate()
    private val pcmBuffer = ByteArrayOutputStream()
    private val writeLock = Any()

    private var connectionJob: Job? = null
    private var recordingTimeoutJob: Job? = null
    private var activeSocket: BluetoothSocket? = null
    private var activeOutput: OutputStream? = null
    private var activeDeviceName = "A9Ultra"
    private var productVerified = false
    private var recording = false
    private var opusFrameLogCount = 0
    private var suppressOpusUntilWake = false
    private var capturedPcmMs = 0L
    private var lastVoicePcmMs = 0L
    private var voiceDetected = false

    private val _state = MutableStateFlow<A9UltraSppState>(A9UltraSppState.Idle)
    val state: StateFlow<A9UltraSppState> = _state

    private val _standbyMode = MutableStateFlow(A9UltraStandbyMode.WAKE_WORD_REQUIRED)
    val standbyMode: StateFlow<A9UltraStandbyMode> = _standbyMode

    fun start() {
        if (connectionJob?.isActive == true) return
        connectionJob = scope.launch {
            while (isActive) {
                runCatching {
                    connectAndReadOnce()
                }.onFailure { error ->
                    Log.w(TAG, "SPP loop failed", error)
                    _state.value = A9UltraSppState.Error(error.message ?: "A9 SPP 连接失败")
                }
                closeActiveSocket()
                productVerified = false
                recording = false
                enterAwaitingWake(reason = "connection-reset")
                recordingTimeoutJob?.cancel()
                if (isActive) delay(RECONNECT_DELAY_MS)
            }
        }
    }

    fun stop() {
        connectionJob?.cancel()
        connectionJob = null
        recordingTimeoutJob?.cancel()
        closeActiveSocket()
        _state.value = A9UltraSppState.Idle
    }

    fun setOpusRecording(enabled: Boolean) {
        send(ABMateSppCommand.OPUS_RECORDING, A9UltraSppPolicy.opusRecordingPayload(enabled))
        if (!enabled) {
            enterAwaitingWake(reason = "manual-off")
            finishSession(closeHeadset = false, reason = "manual-off")
        }
    }

    fun toggleStandbyMode() {
        val nextMode = when (_standbyMode.value) {
            A9UltraStandbyMode.WAKE_WORD_REQUIRED -> A9UltraStandbyMode.CONTINUOUS
            A9UltraStandbyMode.CONTINUOUS -> A9UltraStandbyMode.WAKE_WORD_REQUIRED
        }
        Log.i(TAG, "standby toggle ${_standbyMode.value} -> $nextMode")
        setStandbyMode(nextMode)
    }

    fun setStandbyMode(mode: A9UltraStandbyMode) {
        when (mode) {
            A9UltraStandbyMode.WAKE_WORD_REQUIRED -> {
                rearmWakeWord(reason = "user-standby-wake")
            }
            A9UltraStandbyMode.CONTINUOUS -> {
                if (recording) {
                    openOpusGate()
                } else {
                    enterPostStopDrain(reason = "user-standby-continuous")
                }
            }
        }
    }

    private fun rearmWakeWord(reason: String) {
        Log.i(TAG, "rearm wake word reason=$reason recording=$recording")
        send(ABMateSppCommand.OPUS_RECORDING, A9UltraSppPolicy.opusRecordingPayload(false))
        if (recording) {
            finishSession(closeHeadset = false, reason = reason)
        }
        send(ABMateSppCommand.VOICE_RECOGNITION, A9UltraSppPolicy.voiceRecognitionEnablePayload)
        enterAwaitingWake(reason = reason)
    }

    @SuppressLint("MissingPermission")
    private fun connectAndReadOnce() {
        ensureBluetoothPermission()
        val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter ?: error("设备不支持蓝牙")
        check(adapter.isEnabled) { "蓝牙未开启" }

        _state.value = A9UltraSppState.Searching
        val devices = findCandidateDevices(adapter)
        check(devices.isNotEmpty()) { "未找到已配对 A9Ultra SPP 耳机" }

        var lastError: Throwable? = null
        for (device in devices) {
            for (uuid in A9UltraSppProfile.connectionUuids) {
                val name = device.safeName()
                try {
                    _state.value = A9UltraSppState.Connecting(name, uuid)
                    val socket = device.createRfcommSocketToServiceRecord(uuid)
                    socket.connect()
                    activeSocket = socket
                    activeOutput = socket.outputStream
                    activeDeviceName = name
                    _state.value = A9UltraSppState.Verifying(name)
                    send(ABMateSppCommand.DEVICE_INFO, A9UltraSppPolicy.deviceInfoRequestPayload)
                    readLoop(socket)
                    return
                } catch (error: Throwable) {
                    lastError = error
                    closeActiveSocket()
                    Log.w(TAG, "connect ${name} $uuid failed", error)
                }
            }
        }
        throw lastError ?: IllegalStateException("A9Ultra SPP 连接失败")
    }

    @SuppressLint("MissingPermission")
    private fun findCandidateDevices(adapter: BluetoothAdapter): List<BluetoothDevice> {
        return adapter.bondedDevices
            .filter { device ->
                val name = device.safeName()
                val hasKnownUuid = device.uuids?.any { parcelUuid ->
                    parcelUuid.uuid in A9UltraSppProfile.connectionUuids
                } == true
                hasKnownUuid ||
                    name.contains("A9", ignoreCase = true) ||
                    name.contains("Ultra", ignoreCase = true) ||
                    name.contains("Jin", ignoreCase = true) ||
                    name.contains("金", ignoreCase = true)
            }
            .sortedByDescending { device ->
                device.uuids?.any { it.uuid == A9UltraSppProfile.CUSTOM_SPP_UUID } == true
            }
    }

    private fun readLoop(socket: BluetoothSocket) {
        val buffer = ByteArray(1024)
        val input = socket.inputStream
        while (connectionJob?.isActive == true) {
            val count = input.read(buffer)
            if (count < 0) error("A9 SPP 已断开")
            val chunk = buffer.copyOf(count)
            packetParser.push(chunk).forEach(::handleFrame)
        }
    }

    private fun handleFrame(frame: ABMateSppFrame) {
        logIncomingFrame(frame)
        when (frame.command) {
            ABMateSppCommand.DEVICE_INFO.value,
            ABMateSppCommand.DEVICE_INFO_NOTIFY.value -> {
                handleDeviceInfo(frame)
                logDeviceNotifyTlvs(frame)
                A9UltraSppPolicy.parseWakeEvent(frame)?.let(::handleWakeEvent)
            }
            ABMateSppCommand.OPUS_RECORDING.value -> {
                if (frame.type == ABMateSppFrameType.REQUEST) {
                    sendResponse(ABMateSppCommand.OPUS_RECORDING, A9UltraSppPolicy.successAckPayload(0x01))
                }
                A9UltraSppPolicy.parseOpusRecordingEnabled(frame)?.let { enabled ->
                    if (enabled) {
                        openOpusGate()
                        startSession(reason = "headset-opus-on")
                    } else {
                        if (!opusRecoveryGate.isSuppressing) {
                            enterAwaitingWake(reason = "headset-opus-off")
                        }
                        finishSession(closeHeadset = false, reason = "headset-opus-off")
                    }
                }
            }
            ABMateSppCommand.RECORDING_DATA.value -> {
                A9UltraOpusPacket.parse(frame)?.let(::handleOpusPacket)
            }
        }
    }

    private fun logIncomingFrame(frame: ABMateSppFrame) {
        if (frame.command == ABMateSppCommand.RECORDING_DATA.value) {
            opusFrameLogCount += 1
            if (opusFrameLogCount <= 3 || opusFrameLogCount % 100 == 0) {
                Log.d(TAG, "rx cmd=0x3c type=${frame.type} opusPayload=${frame.payload.size} frame=$opusFrameLogCount")
            }
            return
        }
        Log.d(
            TAG,
            "rx cmd=0x${frame.command.toString(16)} type=${frame.type} payload=${frame.payload.size} ${frame.payload.hexPrefix()}"
        )
    }

    private fun handleDeviceInfo(frame: ABMateSppFrame) {
        if (productVerified || frame.command != ABMateSppCommand.DEVICE_INFO.value) return
        val tlvs = ABMateTlv.parse(frame.payload)
        Log.i(
            TAG,
            "device info ${tlvs.joinToString(" ") { "0x${it.type.toString(16)}=${it.value.hexPrefix(16)}" }}"
        )
        val productId = tlvs.firstOrNull { it.type == 0x24 }?.value?.littleEndianUInt16OrNull()
        val capabilities = tlvs.firstOrNull { it.type == 0xFE }?.value?.littleEndianUInt16OrNull()
        val voiceSupported = capabilities?.let { (it and 0x0010) != 0 }
        Log.i(
            TAG,
            "device gate pid=${productId?.let { "0x${it.toString(16)}" } ?: "-"} capabilities=${capabilities?.let { "0x${it.toString(16)}" } ?: "-"} voice=$voiceSupported"
        )
        check(A9UltraSppPolicy.acceptsSppDeviceInfo(frame.payload, activeDeviceName)) {
            "A9 SPP 设备校验失败: pid=${productId?.let { "0x${it.toString(16)}" } ?: "missing"} name=$activeDeviceName"
        }
        productVerified = true
        _state.value = A9UltraSppState.Ready(activeDeviceName)
        if (voiceSupported == true) {
            send(ABMateSppCommand.VOICE_RECOGNITION, A9UltraSppPolicy.voiceRecognitionEnablePayload)
            Log.i(TAG, "A9Ultra SPP verified, voice recognition enabled")
        } else {
            Log.i(TAG, "A9Ultra SPP verified without AB Mate voice capability bit; waiting for SPP wake/opus")
        }
        if (_standbyMode.value == A9UltraStandbyMode.CONTINUOUS) {
            setStandbyMode(A9UltraStandbyMode.CONTINUOUS)
        } else {
            enterAwaitingWake(reason = "verified")
        }
    }

    private fun logDeviceNotifyTlvs(frame: ABMateSppFrame) {
        if (frame.command != ABMateSppCommand.DEVICE_INFO_NOTIFY.value) return
        val tlvs = ABMateTlv.parse(frame.payload)
        if (tlvs.isEmpty()) return
        Log.d(
            TAG,
            "device notify tlv ${tlvs.joinToString(" ") { "0x${it.type.toString(16)}=${it.value.hexPrefix(16)}" }}"
        )
    }

    private fun handleWakeEvent(event: A9UltraWakeEvent) {
        when (event) {
            is A9UltraWakeEvent.Wake -> {
                Log.i(TAG, "wake notify received side=${event.side}")
                mainScope.launch {
                    onWake()
                }
                openOpusGate()
                promptTonePlayer.play()
                startSession(reason = "wake")
            }
            A9UltraWakeEvent.Sleep -> {
                Log.i(TAG, "sleep notify received")
                enterAwaitingWake(reason = "sleep")
                finishSession(closeHeadset = true, reason = "sleep")
            }
        }
    }

    private fun handleOpusPacket(packet: A9UltraOpusPacket) {
        if (!recording) {
            if (suppressOpusUntilWake) {
                handleSuppressedOpusPacket(packet)
                return
            }
            startSession(reason = "opus")
        }
        val pcm = opusDecoder.decode(packet)
        if (pcm.isNotEmpty()) {
            val level = A9UltraPcmVoiceActivity.analyzePcm16Le(pcm)
            appendDecodedPcm(pcm, level)
        }
    }

    private fun handleSuppressedOpusPacket(packet: A9UltraOpusPacket) {
        val pcm = opusDecoder.decode(packet)
        if (pcm.isEmpty()) return

        val level = A9UltraPcmVoiceActivity.analyzePcm16Le(pcm)
        val decision = opusRecoveryGate.onSuppressedOpus(
            nowMs = System.currentTimeMillis(),
            level = level,
        )
        logSuppressedOpusDecision(decision, level)
        if (decision != A9UltraOpusRecoveryDecision.StartRecovery) return

        openOpusGate()
        startSession(reason = "opus-recovery", resetDecoder = false)
        if (!recording) return
        appendDecodedPcm(pcm, level)
    }

    private fun logSuppressedOpusDecision(decision: A9UltraOpusRecoveryDecision, level: A9UltraPcmLevel) {
        val frames = opusRecoveryGate.ignoredFrames
        if (decision == A9UltraOpusRecoveryDecision.StartRecovery) {
            Log.i(
                TAG,
                "suppressed opus recovered frames=$frames avg=${level.averageAbs} peak=${level.peakAbs}"
            )
            return
        }
        if (frames <= 3 || frames % 100 == 0) {
            Log.d(
                TAG,
                "suppressed opus ignored decision=$decision frames=$frames avg=${level.averageAbs} peak=${level.peakAbs}"
            )
        }
    }

    private fun appendDecodedPcm(pcm: ByteArray, level: A9UltraPcmLevel) {
        pcmBuffer.write(pcm)
        capturedPcmMs += level.durationMs
        if (level.isVoice) {
            voiceDetected = true
            lastVoicePcmMs = capturedPcmMs
        }
        _state.value = A9UltraSppState.Recording(activeDeviceName, pcmBuffer.size())
        maybeFinishForVoiceActivity()
    }

    private fun startSession(reason: String, resetDecoder: Boolean = true) {
        if (!productVerified) return
        if (!recording) {
            openOpusGate()
            recording = true
            opusFrameLogCount = 0
            capturedPcmMs = 0L
            lastVoicePcmMs = 0L
            voiceDetected = false
            pcmBuffer.reset()
            if (resetDecoder) {
                opusDecoder.reset()
            }
            _state.value = A9UltraSppState.Recording(activeDeviceName, 0)
            scheduleRecordingTimeout()
            Log.i(TAG, "recording started reason=$reason")
        }
    }

    private fun finishSession(closeHeadset: Boolean, reason: String) {
        recordingTimeoutJob?.cancel()
        if (closeHeadset) {
            send(ABMateSppCommand.OPUS_RECORDING, A9UltraSppPolicy.opusRecordingPayload(false))
        }
        if (!recording) return
        recording = false
        _state.value = if (productVerified) A9UltraSppState.Ready(activeDeviceName) else A9UltraSppState.Idle
        val pcm = pcmBuffer.toByteArray()
        pcmBuffer.reset()
        if (pcm.isEmpty()) {
            Log.i(TAG, "recording dropped reason=$reason empty=true")
            return
        }
        val wav = HeadsetWavEncoder.encodePcm16Mono16k(pcm)
        Log.i(TAG, "recording finished reason=$reason pcm=${pcm.size} wav=${wav.size} voice=$voiceDetected")
        mainScope.launch {
            onAudioReady(wav)
        }
    }

    private fun maybeFinishForVoiceActivity() {
        val silenceMs = capturedPcmMs - lastVoicePcmMs
        when {
            voiceDetected && capturedPcmMs >= MIN_RECORDING_MS && silenceMs >= END_SILENCE_MS -> {
                stopHeadsetRecording(reason = "speech-end")
            }
            !voiceDetected && capturedPcmMs >= NO_SPEECH_TIMEOUT_MS -> {
                stopHeadsetRecording(reason = "no-speech")
            }
        }
    }

    private fun stopHeadsetRecording(reason: String) {
        enterPostStopDrain(reason = reason)
        send(ABMateSppCommand.OPUS_RECORDING, A9UltraSppPolicy.opusRecordingPayload(false))
        finishSession(closeHeadset = false, reason = reason)
    }

    private fun scheduleRecordingTimeout() {
        recordingTimeoutJob?.cancel()
        recordingTimeoutJob = scope.launch {
            delay(maxRecordingMs)
            if (!recording) return@launch
            enterPostStopDrain(reason = "max-timeout")
            send(ABMateSppCommand.OPUS_RECORDING, A9UltraSppPolicy.opusRecordingPayload(false))
            finishSession(closeHeadset = false, reason = "max-timeout")
        }
    }

    private fun openOpusGate() {
        suppressOpusUntilWake = false
        opusRecoveryGate.open()
        _standbyMode.value = opusRecoveryGate.standbyMode
    }

    private fun enterAwaitingWake(reason: String) {
        suppressOpusUntilWake = true
        opusRecoveryGate.enterAwaitingWake(System.currentTimeMillis())
        _standbyMode.value = opusRecoveryGate.standbyMode
        Log.d(TAG, "opus suppress awaiting wake reason=$reason")
    }

    private fun enterPostStopDrain(reason: String) {
        suppressOpusUntilWake = true
        opusRecoveryGate.enterPostStopDrain(System.currentTimeMillis())
        _standbyMode.value = opusRecoveryGate.standbyMode
        Log.d(TAG, "opus suppress post-stop drain reason=$reason")
    }

    private fun send(command: ABMateSppCommand, payload: ByteArray = ByteArray(0)) {
        observeCommand(command, payload)
        send(command.value, ABMateSppFrameType.REQUEST, payload)
    }

    private fun sendResponse(command: ABMateSppCommand, payload: ByteArray = ByteArray(0)) {
        send(command.value, ABMateSppFrameType.RESPONSE, payload)
    }

    private fun send(command: Int, type: ABMateSppFrameType, payload: ByteArray = ByteArray(0)) {
        val output = activeOutput ?: return
        val bytes = frameCodec.encode(command, type, payload)
        synchronized(writeLock) {
            output.write(bytes)
            output.flush()
        }
        Log.d(TAG, "tx cmd=0x${command.toString(16)} type=$type payload=${payload.size}")
    }

    private fun ensureBluetoothPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            error("缺少蓝牙连接权限")
        }
    }

    private fun closeActiveSocket() {
        runCatching { activeOutput?.close() }
        activeOutput = null
        runCatching { activeSocket?.close() }
        activeSocket = null
    }

    @SuppressLint("MissingPermission")
    private fun BluetoothDevice.safeName(): String = runCatching { name }.getOrNull().orEmpty().ifBlank { address }

    companion object {
        private const val TAG = "A9UltraSPP"
        private const val RECONNECT_DELAY_MS = 3_000L
        private const val MIN_RECORDING_MS = 900L
        private const val END_SILENCE_MS = 2_500L
        private const val NO_SPEECH_TIMEOUT_MS = 4_000L
    }
}

private class A9UltraOpusDecoder {
    private var decoder = OpusDecoder(SAMPLE_RATE, CHANNELS)

    fun reset() {
        decoder = OpusDecoder(SAMPLE_RATE, CHANNELS)
    }

    fun decode(packet: A9UltraOpusPacket): ByteArray {
        if (packet.opusData.isEmpty()) return ByteArray(0)
        val frameSize = packet.frameSize.takeIf { it > 0 }
        val frames = if (frameSize != null && packet.frameCount * frameSize <= packet.opusData.size) {
            (0 until packet.frameCount).map { index ->
                val start = index * frameSize
                packet.opusData.copyOfRange(start, start + frameSize)
            }
        } else {
            listOf(packet.opusData)
        }

        val out = ByteArrayOutputStream()
        val pcm = ShortArray(MAX_FRAME_SAMPLES)
        frames.forEach { opus ->
            val samples = decoder.decode(opus, 0, opus.size, pcm, 0, MAX_FRAME_SAMPLES, false)
            for (index in 0 until samples * CHANNELS) {
                val sample = pcm[index].toInt()
                out.write(sample and 0xFF)
                out.write((sample ushr 8) and 0xFF)
            }
        }
        return out.toByteArray()
    }

    companion object {
        private const val SAMPLE_RATE = 16_000
        private const val CHANNELS = 1
        private const val MAX_FRAME_SAMPLES = 1_920
    }
}

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
    private val idleTimeoutMs: Long = 60_000L,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val frameCodec = ABMateSppFrameCodec()
    private val packetParser = ABMateSppPacketParser()
    private val opusDecoder = A9UltraOpusDecoder()
    private val pcmBuffer = ByteArrayOutputStream()
    private val writeLock = Any()

    private var connectionJob: Job? = null
    private var idleTimeoutJob: Job? = null
    private var activeSocket: BluetoothSocket? = null
    private var activeOutput: OutputStream? = null
    private var activeDeviceName = "A9Ultra"
    private var productVerified = false
    private var recording = false

    private val _state = MutableStateFlow<A9UltraSppState>(A9UltraSppState.Idle)
    val state: StateFlow<A9UltraSppState> = _state

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
                idleTimeoutJob?.cancel()
                if (isActive) delay(RECONNECT_DELAY_MS)
            }
        }
    }

    fun stop() {
        connectionJob?.cancel()
        connectionJob = null
        idleTimeoutJob?.cancel()
        closeActiveSocket()
        _state.value = A9UltraSppState.Idle
    }

    fun setOpusRecording(enabled: Boolean) {
        send(ABMateSppCommand.OPUS_RECORDING, A9UltraSppPolicy.opusRecordingPayload(enabled))
        if (!enabled) {
            finishSession(closeHeadset = false)
        }
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
        Log.d(TAG, "rx cmd=0x${frame.command.toString(16)} type=${frame.type} payload=${frame.payload.size}")
        when (frame.command) {
            ABMateSppCommand.DEVICE_INFO.value,
            ABMateSppCommand.DEVICE_INFO_NOTIFY.value -> {
                handleDeviceInfo(frame)
                A9UltraSppPolicy.parseWakeEvent(frame)?.let(::handleWakeEvent)
            }
            ABMateSppCommand.OPUS_RECORDING.value -> {
                if (frame.type == ABMateSppFrameType.REQUEST) {
                    sendResponse(ABMateSppCommand.OPUS_RECORDING, A9UltraSppPolicy.successAckPayload(0x01))
                }
                A9UltraSppPolicy.parseOpusRecordingEnabled(frame)?.let { enabled ->
                    if (enabled) startSession() else finishSession(closeHeadset = false)
                }
            }
            ABMateSppCommand.RECORDING_DATA.value -> {
                A9UltraOpusPacket.parse(frame)?.let(::handleOpusPacket)
            }
        }
    }

    private fun handleDeviceInfo(frame: ABMateSppFrame) {
        if (productVerified || frame.command != ABMateSppCommand.DEVICE_INFO.value) return
        check(A9UltraSppPolicy.acceptsDeviceInfo(frame.payload)) {
            "A9 PID/语音识别能力校验失败"
        }
        productVerified = true
        _state.value = A9UltraSppState.Ready(activeDeviceName)
        send(ABMateSppCommand.VOICE_RECOGNITION, A9UltraSppPolicy.voiceRecognitionEnablePayload)
        Log.i(TAG, "A9Ultra SPP verified, voice recognition enabled")
    }

    private fun handleWakeEvent(event: A9UltraWakeEvent) {
        when (event) {
            is A9UltraWakeEvent.Wake -> startSession()
            A9UltraWakeEvent.Sleep -> finishSession(closeHeadset = true)
        }
    }

    private fun handleOpusPacket(packet: A9UltraOpusPacket) {
        if (!recording) startSession()
        val pcm = opusDecoder.decode(packet)
        if (pcm.isNotEmpty()) {
            pcmBuffer.write(pcm)
            _state.value = A9UltraSppState.Recording(activeDeviceName, pcmBuffer.size())
        }
        scheduleIdleTimeout()
    }

    private fun startSession() {
        if (!productVerified) return
        if (!recording) {
            recording = true
            pcmBuffer.reset()
            opusDecoder.reset()
            _state.value = A9UltraSppState.Recording(activeDeviceName, 0)
        }
        scheduleIdleTimeout()
    }

    private fun finishSession(closeHeadset: Boolean) {
        idleTimeoutJob?.cancel()
        if (closeHeadset) {
            send(ABMateSppCommand.OPUS_RECORDING, A9UltraSppPolicy.opusRecordingPayload(false))
        }
        if (!recording) return
        recording = false
        _state.value = if (productVerified) A9UltraSppState.Ready(activeDeviceName) else A9UltraSppState.Idle
        val pcm = pcmBuffer.toByteArray()
        pcmBuffer.reset()
        if (pcm.isEmpty()) return
        val wav = HeadsetWavEncoder.encodePcm16Mono16k(pcm)
        mainScope.launch {
            onAudioReady(wav)
        }
    }

    private fun scheduleIdleTimeout() {
        idleTimeoutJob?.cancel()
        idleTimeoutJob = scope.launch {
            delay(idleTimeoutMs)
            send(ABMateSppCommand.OPUS_RECORDING, A9UltraSppPolicy.opusRecordingPayload(false))
            finishSession(closeHeadset = false)
        }
    }

    private fun send(command: ABMateSppCommand, payload: ByteArray = ByteArray(0)) {
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

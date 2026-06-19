package com.openclaw.remote.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

enum class RecordingType(val wireValue: String, val label: String) {
    AUDIO_ONLY("audio_only", "普通录音"),
    MEETING("meeting", "会议"),
    IDEA("idea", "灵感"),
    CUSTOM("custom", "自定义");

    companion object {
        fun fromWireValue(value: String?): RecordingType =
            entries.firstOrNull { it.wireValue == value?.trim()?.lowercase() } ?: MEETING
    }
}

data class RecordingSettings(
    val defaultType: RecordingType = RecordingType.MEETING,
    val asrMode: String = "router",
    val asrProfileId: String? = null,
    val customPrompt: String = "",
)

fun RecordingSettings.settingsTypeOptions(): List<RecordingType> =
    RecordingType.entries.toList()

fun RecordingSettings.recordingSelectionTypeOptions(): List<RecordingType> =
    settingsTypeOptions().filter { type ->
        type != RecordingType.CUSTOM || customPrompt.isNotBlank()
    }

fun RecordingSettings.defaultSelectionType(): RecordingType {
    val options = recordingSelectionTypeOptions()
    return defaultType.takeIf { it in options } ?: options.first()
}

fun RecordingSettings.promptFor(type: RecordingType): String =
    when (type) {
        RecordingType.AUDIO_ONLY -> ""
        RecordingType.MEETING -> RecordingPrompts.meeting
        RecordingType.IDEA -> RecordingPrompts.idea
        RecordingType.CUSTOM -> customPrompt.trim()
    }

object RecordingPrompts {
    const val meeting: String = "以下是会议录音。请根据录音整理会议纪要、Agent 可承接的待办、需要人完成的待办，并输出后续执行计划。"
    const val idea: String = "以下是灵感记录。请整理为研究型灵感报告，补充背景、风险、方案和行动项。"
}

enum class RecordingAsrJobStatus {
    QUEUED,
    UPLOADING,
    PROCESSING,
    COMPLETED,
    FAILED;

    companion object {
        fun fromWireValue(value: String?): RecordingAsrJobStatus =
            entries.firstOrNull { it.name.lowercase() == value?.trim()?.lowercase() } ?: PROCESSING
    }
}

data class RecordingAsrJob(
    val jobId: String,
    val status: RecordingAsrJobStatus,
    val progress: Double,
    val error: String? = null,
    val updatedAt: Long = currentTimestampMillis(),
)

data class RecordingArtifact(
    val id: String,
    val filename: String,
    val mimeType: String? = null,
    val path: String? = null,
    val retrievalRef: String? = null,
    val content: String? = null,
)

data class RecordingEvent(
    val id: String,
    val recordingId: String,
    val kind: String,
    val title: String,
    val body: String? = null,
    val createdAt: Long = currentTimestampMillis(),
    val artifact: RecordingArtifact? = null,
)

data class RecordingReminder(
    val id: String,
    val title: String,
    val dueAt: String? = null,
    val isDone: Boolean = false,
)

data class Recording(
    val id: String,
    val title: String,
    val type: RecordingType,
    val audioPath: String,
    val durationMillis: Long,
    val createdAt: Long,
    val updatedAt: Long,
    val asrText: String = "",
    val asrJob: RecordingAsrJob? = null,
    val events: List<RecordingEvent> = emptyList(),
    val reminders: List<RecordingReminder> = emptyList(),
)

class RecordingStore(initialRecordings: List<Recording> = emptyList()) {
    var recordings: List<Recording> = initialRecordings.sortedByDescending { it.createdAt }
        private set

    fun createRecording(
        title: String,
        type: RecordingType,
        audioPath: String,
        durationMillis: Long,
        nowMillis: Long = currentTimestampMillis(),
    ): Recording {
        val recording = Recording(
            id = "recording_${randomUuid().take(8)}",
            title = title.trim().ifEmpty { type.label },
            type = type,
            audioPath = audioPath,
            durationMillis = durationMillis,
            createdAt = nowMillis,
            updatedAt = nowMillis,
        )
        recordings = (recordings + recording).sortedByDescending { it.createdAt }
        return recording
    }

    fun deleteRecording(recordingId: String) {
        recordings = recordings.filterNot { it.id == recordingId }
    }

    fun updateAsrJob(recordingId: String, job: RecordingAsrJob) {
        updateRecording(recordingId) { it.copy(asrJob = job, updatedAt = job.updatedAt) }
    }

    fun updateAsrText(recordingId: String, text: String, updatedAt: Long = currentTimestampMillis()) {
        updateRecording(recordingId) { it.copy(asrText = text, updatedAt = updatedAt) }
    }

    fun addReminder(recordingId: String, reminder: RecordingReminder) {
        updateRecording(recordingId) {
            it.copy(reminders = it.reminders.filterNot { item -> item.id == reminder.id } + reminder)
        }
    }

    fun appendEvent(event: RecordingEvent) {
        updateRecording(event.recordingId) {
            it.copy(
                events = (it.events.filterNot { item -> item.id == event.id } + event)
                    .sortedBy { item -> item.createdAt },
                updatedAt = maxOf(it.updatedAt, event.createdAt),
            )
        }
    }

    private fun updateRecording(recordingId: String, transform: (Recording) -> Recording) {
        recordings = recordings.map { recording ->
            if (recording.id == recordingId) transform(recording) else recording
        }.sortedByDescending { it.createdAt }
    }
}

fun encodeRecordings(recordings: List<Recording>): String =
    buildJsonArray {
        recordings.forEach { recording ->
            add(recording.toJson())
        }
    }.toString()

fun decodeRecordings(raw: String?): List<Recording> {
    if (raw.isNullOrBlank()) return emptyList()
    return runCatching {
        Json.parseToJsonElement(raw).jsonArray.mapNotNull { (it as? JsonObject)?.toRecording() }
    }.getOrDefault(emptyList())
}

private fun Recording.toJson(): JsonObject =
    buildJsonObject {
        put("id", id)
        put("title", title)
        put("type", type.wireValue)
        put("audioPath", audioPath)
        put("durationMillis", durationMillis)
        put("createdAt", createdAt)
        put("updatedAt", updatedAt)
        put("asrText", asrText)
        asrJob?.let { put("asrJob", it.toJson()) }
        put("events", buildJsonArray { events.forEach { add(it.toJson()) } })
        put("reminders", buildJsonArray { reminders.forEach { add(it.toJson()) } })
    }

private fun RecordingAsrJob.toJson(): JsonObject =
    buildJsonObject {
        put("jobId", jobId)
        put("status", status.name.lowercase())
        put("progress", progress)
        error?.let { put("error", it) }
        put("updatedAt", updatedAt)
    }

private fun RecordingEvent.toJson(): JsonObject =
    buildJsonObject {
        put("id", id)
        put("recordingId", recordingId)
        put("kind", kind)
        put("title", title)
        body?.let { put("body", it) }
        put("createdAt", createdAt)
        artifact?.let { put("artifact", it.toJson()) }
    }

private fun RecordingArtifact.toJson(): JsonObject =
    buildJsonObject {
        put("id", id)
        put("filename", filename)
        mimeType?.let { put("mimeType", it) }
        path?.let { put("path", it) }
        retrievalRef?.let { put("retrievalRef", it) }
        content?.let { put("content", it) }
    }

private fun RecordingReminder.toJson(): JsonObject =
    buildJsonObject {
        put("id", id)
        put("title", title)
        dueAt?.let { put("dueAt", it) }
        put("isDone", isDone)
    }

private fun JsonObject.toRecording(): Recording =
    Recording(
        id = string("id"),
        title = string("title").ifBlank { "录音" },
        type = RecordingType.fromWireValue(string("type")),
        audioPath = string("audioPath"),
        durationMillis = long("durationMillis"),
        createdAt = long("createdAt"),
        updatedAt = long("updatedAt"),
        asrText = string("asrText"),
        asrJob = (this["asrJob"] as? JsonObject)?.toRecordingAsrJob(),
        events = objectArray("events").map { it.toRecordingEvent() },
        reminders = objectArray("reminders").map { it.toRecordingReminder() },
    )

private fun JsonObject.toRecordingAsrJob(): RecordingAsrJob =
    RecordingAsrJob(
        jobId = string("jobId"),
        status = RecordingAsrJobStatus.fromWireValue(string("status")),
        progress = double("progress"),
        error = stringOrNull("error"),
        updatedAt = long("updatedAt"),
    )

private fun JsonObject.toRecordingEvent(): RecordingEvent =
    RecordingEvent(
        id = string("id"),
        recordingId = string("recordingId"),
        kind = string("kind"),
        title = string("title"),
        body = stringOrNull("body"),
        createdAt = long("createdAt"),
        artifact = (this["artifact"] as? JsonObject)?.toRecordingArtifact(),
    )

private fun JsonObject.toRecordingArtifact(): RecordingArtifact =
    RecordingArtifact(
        id = string("id"),
        filename = string("filename"),
        mimeType = stringOrNull("mimeType"),
        path = stringOrNull("path"),
        retrievalRef = stringOrNull("retrievalRef"),
        content = stringOrNull("content"),
    )

private fun JsonObject.toRecordingReminder(): RecordingReminder =
    RecordingReminder(
        id = string("id"),
        title = string("title"),
        dueAt = stringOrNull("dueAt"),
        isDone = this["isDone"]?.jsonPrimitive?.booleanOrNull ?: false,
    )

private fun JsonObject.string(name: String): String =
    this[name]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()

private fun JsonObject.stringOrNull(name: String): String? =
    string(name).takeIf { it.isNotBlank() }

private fun JsonObject.long(name: String): Long =
    this[name]?.jsonPrimitive?.longOrNull ?: 0L

private fun JsonObject.double(name: String): Double =
    this[name]?.jsonPrimitive?.doubleOrNull ?: 0.0

private fun JsonObject.objectArray(name: String): List<JsonObject> =
    (this[name] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

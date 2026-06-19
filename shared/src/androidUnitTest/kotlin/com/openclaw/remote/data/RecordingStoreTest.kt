package com.openclaw.remote.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

class RecordingStoreTest {
    @Test
    fun createsUpdatesAndDeletesRecordingsInMemorySnapshot() {
        val store = RecordingStore()

        val recording = store.createRecording(
            title = "周会录音",
            type = RecordingType.MEETING,
            audioPath = "/tmp/meeting.wav",
            durationMillis = 12_000,
            nowMillis = 1_000,
        )
        store.updateAsrJob(
            recording.id,
            RecordingAsrJob(
                jobId = "job-1",
                status = RecordingAsrJobStatus.PROCESSING,
                progress = 0.4,
                updatedAt = 2_000,
            ),
        )
        store.updateAsrText(recording.id, "整理后的纪要", updatedAt = 3_000)
        store.addReminder(recording.id, RecordingReminder(id = "todo-1", title = "跟进报价", dueAt = "2026-06-13T10:00:00Z"))
        store.appendEvent(
            RecordingEvent(
                id = "event-1",
                recordingId = recording.id,
                kind = "artifact",
                title = "报告已生成",
                body = "report.md",
                createdAt = 4_000,
                artifact = RecordingArtifact(
                    id = "artifact-1",
                    filename = "report.md",
                    mimeType = "text/markdown",
                    path = "/tmp/report.md",
                ),
            )
        )

        val updated = store.recordings.single()
        assertEquals("整理后的纪要", updated.asrText)
        assertEquals(RecordingAsrJobStatus.PROCESSING, updated.asrJob?.status)
        assertEquals(0.4, updated.asrJob?.progress)
        assertEquals("跟进报价", updated.reminders.single().title)
        assertEquals("report.md", updated.events.single().artifact?.filename)

        store.deleteRecording(recording.id)

        assertFalse(store.recordings.any { it.id == recording.id })
    }

    @Test
    fun failedAsrJobStoresFailureAndKeepsRecordingVisible() {
        val store = RecordingStore()
        val recording = store.createRecording("灵感", RecordingType.IDEA, "/tmp/idea.wav", 1_000, nowMillis = 1_000)

        store.updateAsrJob(
            recording.id,
            RecordingAsrJob(
                jobId = "job-2",
                status = RecordingAsrJobStatus.FAILED,
                progress = 1.0,
                error = "ASR_TIMEOUT",
                updatedAt = 2_000,
            ),
        )

        assertEquals(1, store.recordings.size)
        assertEquals(RecordingAsrJobStatus.FAILED, store.recordings.single().asrJob?.status)
        assertEquals("ASR_TIMEOUT", store.recordings.single().asrJob?.error)
    }

    @Test
    fun recordingSettingsDefaultToRouterAsrAndMeetingType() {
        val settings = RecordingSettings()

        assertEquals(RecordingType.MEETING, settings.defaultType)
        assertEquals("router", settings.asrMode)
        assertNull(settings.asrProfileId)
    }

    @Test
    fun recordingSettingsShowCustomInSettingsButHideBlankCustomWhenSelectingRecording() {
        val emptyCustom = RecordingSettings(defaultType = RecordingType.CUSTOM, customPrompt = "  ")

        assertEquals(RecordingType.entries.toList(), emptyCustom.settingsTypeOptions())
        assertEquals(
            listOf(RecordingType.AUDIO_ONLY, RecordingType.MEETING, RecordingType.IDEA),
            emptyCustom.recordingSelectionTypeOptions(),
        )
        assertEquals(RecordingType.AUDIO_ONLY, emptyCustom.defaultSelectionType())

        val configuredCustom = emptyCustom.copy(customPrompt = "请按我的模板处理录音")

        assertEquals(RecordingType.entries.toList(), configuredCustom.recordingSelectionTypeOptions())
        assertEquals(RecordingType.CUSTOM, configuredCustom.defaultSelectionType())
    }

    @Test
    fun encodesAndDecodesRecordingSnapshots() {
        val store = RecordingStore()
        val recording = store.createRecording("周会", RecordingType.MEETING, "/tmp/meeting.wav", 3_000, nowMillis = 1_000)
        store.updateAsrText(recording.id, "纪要", updatedAt = 2_000)
        store.addReminder(recording.id, RecordingReminder(id = "reminder-1", title = "发报告"))

        val decoded = decodeRecordings(encodeRecordings(store.recordings))

        assertEquals(1, decoded.size)
        assertEquals("周会", decoded.single().title)
        assertEquals(RecordingType.MEETING, decoded.single().type)
        assertEquals("纪要", decoded.single().asrText)
        assertEquals("发报告", decoded.single().reminders.single().title)
    }
}

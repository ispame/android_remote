package com.openclaw.remote.network

import com.openclaw.remote.data.RecordingAsrJobStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class WebSocketRecordingEventTest {
    @Test
    fun parsesRecordingEventFrame() {
        val event = parseWsMessageEventForTest(
            """
            {
              "type": "recording_event",
              "recording_id": "recording-1",
              "event_id": "event-1",
              "kind": "artifact",
              "title": "报告已生成",
              "body": "report.md",
              "created_at": 1700000000000,
              "artifact": {
                "artifact_id": "artifact-1",
                "filename": "report.md",
                "mime_type": "text/markdown",
                "path": "/tmp/report.md"
              }
            }
            """.trimIndent()
        )

        val recordingEvent = assertIs<WsMessageEvent.RecordingEventReceived>(event)
        assertEquals("recording-1", recordingEvent.event.recordingId)
        assertEquals("artifact", recordingEvent.event.kind)
        assertEquals("report.md", recordingEvent.event.artifact?.filename)
    }

    @Test
    fun parsesLongRecordingAsrStatusFrame() {
        val event = parseWsMessageEventForTest(
            """
            {
              "type": "long_recording_asr_status",
              "recording_id": "recording-1",
              "job_id": "job-1",
              "status": "completed",
              "progress": 1.0,
              "text": "转写完成",
              "updated_at": 1700000000001
            }
            """.trimIndent()
        )

        val status = assertIs<WsMessageEvent.LongRecordingAsrStatusReceived>(event)
        assertEquals("recording-1", status.recordingId)
        assertEquals("job-1", status.job.jobId)
        assertEquals(RecordingAsrJobStatus.COMPLETED, status.job.status)
        assertEquals("转写完成", status.text)
    }
}

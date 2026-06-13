package com.openclaw.remote.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals

class RecordingWorkflowTest {
    @Test
    fun parsesV2SnapshotAndKeepsProgressOutcomeAware() {
        val json = Json.parseToJsonElement(
            """
            {
              "workflow_id": "workflow-1",
              "account_id": "account-1",
              "backend_id": "backend-1",
              "recording_id": "recording-1",
              "title": "Research report",
              "status": "partial",
              "revision": 7,
              "quality_state": "completed_with_gaps",
              "warnings": ["CXMT premise is unverified"],
              "final_artifact": {
                "artifact_id": "report-1",
                "filename": "report.md",
                "mime_type": "text/markdown",
                "sha256": "abc",
                "size_bytes": 10,
                "retrieval_ref": "/api/recording-workflows/workflow-1/artifacts/final"
              },
              "tasks": [
                {
                  "task_id": "spacex",
                  "workflow_id": "workflow-1",
                  "title": "SpaceX",
                  "prompt": "Research SpaceX",
                  "status": "degraded",
                  "attempt": 1,
                  "max_attempts": 2,
                  "executor_hint": "hermes",
                  "model_hint": "research-model",
                  "source_constraints": ["official", "primary"],
                  "confidence": 0.72,
                  "warnings": ["Evidence quarantined"],
                  "blocking_task_ids": [],
                  "available_actions": ["retry", "skip"],
                  "depends_on": [],
                  "evidence": []
                },
                {
                  "task_id": "cxmt",
                  "workflow_id": "workflow-1",
                  "title": "CXMT",
                  "prompt": "Research CXMT",
                  "status": "blocked",
                  "attempt": 1,
                  "max_attempts": 2,
                  "blocking_task_ids": ["spacex"],
                  "available_actions": ["retry_blockers", "skip"],
                  "depends_on": ["spacex"],
                  "evidence": []
                },
                {
                  "task_id": "summary",
                  "workflow_id": "workflow-1",
                  "system_kind": "summary",
                  "title": "Summary",
                  "prompt": "Summarize",
                  "status": "succeeded",
                  "attempt": 0,
                  "max_attempts": 1,
                  "depends_on": ["spacex", "cxmt"],
                  "evidence": []
                }
              ]
            }
            """.trimIndent()
        ).jsonObject

        val workflow = parseRecordingWorkflow(json)

        assertEquals(7, workflow.revision)
        assertEquals(2, workflow.businessTaskCount)
        assertEquals(0, workflow.successfulTaskCount)
        assertEquals(1, workflow.degradedTaskCount)
        assertEquals(1, workflow.blockedTaskCount)
        assertEquals(0.5, workflow.progress)
        assertEquals("hermes", workflow.tasks[0].executorHint)
        assertEquals("research-model", workflow.tasks[0].modelHint)
        assertEquals(listOf("official", "primary"), workflow.tasks[0].sourceConstraints)
        assertEquals(listOf("spacex"), workflow.tasks[1].blockingTaskIds)
        assertEquals(listOf("retry_blockers", "skip"), workflow.tasks[1].availableActions)
        assertEquals("report.md", workflow.finalArtifact?.filename)
    }
}

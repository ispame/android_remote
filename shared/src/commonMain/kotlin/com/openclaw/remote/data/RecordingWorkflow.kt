package com.openclaw.remote.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

data class RecordingWorkflowArtifact(
    val artifactId: String?,
    val filename: String,
    val mimeType: String?,
    val sha256: String?,
    val sizeBytes: Int?,
    val retrievalRef: String?,
    val downloadUrl: String?,
    val content: String?,
)

data class RecordingWorkflowEvidence(
    val type: String,
    val description: String,
    val path: String?,
    val url: String?,
    val sha256: String?,
    val receiptId: String?,
    val verified: Boolean?,
)

data class RecordingWorkflowTask(
    val taskId: String,
    val workflowId: String,
    val systemKind: String?,
    val title: String,
    val prompt: String,
    val status: String,
    val attempt: Int,
    val maxAttempts: Int,
    val criticality: String?,
    val dependencyPolicy: String?,
    val failurePolicy: String?,
    val executorHint: String?,
    val modelHint: String?,
    val sourceConstraints: List<String>,
    val confidence: Double?,
    val warnings: List<String>,
    val dependsOn: List<String>,
    val blockingTaskIds: List<String>,
    val availableActions: List<String>,
    val resultSummary: String?,
    val lastError: String?,
    val rawOutputRef: String?,
    val evidence: List<RecordingWorkflowEvidence>,
) {
    val isDelivered: Boolean
        get() = status == "succeeded" || status == "degraded"
}

data class RecordingWorkflow(
    val workflowId: String,
    val accountId: String,
    val backendId: String,
    val recordingId: String,
    val title: String,
    val status: String,
    val revision: Int,
    val deadlineAt: String?,
    val qualityState: String?,
    val summary: String?,
    val warnings: List<String>,
    val finalArtifact: RecordingWorkflowArtifact?,
    val tasks: List<RecordingWorkflowTask>,
) {
    val businessTasks: List<RecordingWorkflowTask>
        get() = tasks.filter { it.systemKind != "summary" }
    val businessTaskCount: Int
        get() = businessTasks.size
    val successfulTaskCount: Int
        get() = businessTasks.count { it.status == "succeeded" }
    val degradedTaskCount: Int
        get() = businessTasks.count { it.status == "degraded" }
    val failedTaskCount: Int
        get() = businessTasks.count { it.status == "failed" }
    val blockedTaskCount: Int
        get() = businessTasks.count { it.status == "blocked" }
    val cancelledTaskCount: Int
        get() = businessTasks.count { it.status == "cancelled" }
    val deliveredTaskCount: Int
        get() = businessTasks.count(RecordingWorkflowTask::isDelivered)
    val progress: Double
        get() = if (businessTaskCount == 0) {
            if (status in terminalWorkflowStatuses) 1.0 else 0.0
        } else {
            deliveredTaskCount.toDouble() / businessTaskCount.toDouble()
        }
    val isTerminal: Boolean
        get() = status in terminalWorkflowStatuses
}

fun parseRecordingWorkflow(json: JsonObject): RecordingWorkflow {
    return RecordingWorkflow(
        workflowId = json.requiredString("workflow_id"),
        accountId = json.string("account_id"),
        backendId = json.string("backend_id"),
        recordingId = json.string("recording_id"),
        title = json.string("title").ifBlank { "录音执行工作流" },
        status = json.string("status").ifBlank { "running" },
        revision = json.int("revision") ?: 1,
        deadlineAt = json.stringOrNull("deadline_at"),
        qualityState = json.stringOrNull("quality_state"),
        summary = json.stringOrNull("summary"),
        warnings = json.stringList("warnings"),
        finalArtifact = (json["final_artifact"] as? JsonObject)?.toRecordingWorkflowArtifact(),
        tasks = json.objectList("tasks").map(JsonObject::toRecordingWorkflowTask),
    )
}

private fun JsonObject.toRecordingWorkflowTask(): RecordingWorkflowTask {
    return RecordingWorkflowTask(
        taskId = requiredString("task_id"),
        workflowId = string("workflow_id"),
        systemKind = stringOrNull("system_kind"),
        title = string("title").ifBlank { requiredString("task_id") },
        prompt = string("prompt"),
        status = string("status").ifBlank { "planned" },
        attempt = int("attempt") ?: 0,
        maxAttempts = int("max_attempts") ?: 2,
        criticality = stringOrNull("criticality"),
        dependencyPolicy = stringOrNull("dependency_policy"),
        failurePolicy = stringOrNull("failure_policy"),
        executorHint = stringOrNull("executor_hint"),
        modelHint = stringOrNull("model_hint"),
        sourceConstraints = stringList("source_constraints"),
        confidence = this["confidence"]?.jsonPrimitive?.doubleOrNull,
        warnings = stringList("warnings"),
        dependsOn = stringList("depends_on"),
        blockingTaskIds = stringList("blocking_task_ids"),
        availableActions = stringList("available_actions"),
        resultSummary = stringOrNull("result_summary"),
        lastError = stringOrNull("last_error"),
        rawOutputRef = stringOrNull("raw_output_ref"),
        evidence = objectList("evidence").map(JsonObject::toRecordingWorkflowEvidence),
    )
}

private fun JsonObject.toRecordingWorkflowEvidence(): RecordingWorkflowEvidence {
    return RecordingWorkflowEvidence(
        type = string("type"),
        description = string("description"),
        path = stringOrNull("path"),
        url = stringOrNull("url"),
        sha256 = stringOrNull("sha256"),
        receiptId = stringOrNull("receipt_id"),
        verified = this["verified"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull(),
    )
}

private fun JsonObject.toRecordingWorkflowArtifact(): RecordingWorkflowArtifact {
    return RecordingWorkflowArtifact(
        artifactId = stringOrNull("artifact_id"),
        filename = string("filename").ifBlank { "report.md" },
        mimeType = stringOrNull("mime_type"),
        sha256 = stringOrNull("sha256"),
        sizeBytes = int("size_bytes"),
        retrievalRef = stringOrNull("retrieval_ref"),
        downloadUrl = stringOrNull("download_url"),
        content = stringOrNull("content"),
    )
}

private fun JsonObject.requiredString(name: String): String =
    string(name).takeIf(String::isNotBlank) ?: error("Missing recording workflow field: $name")

private fun JsonObject.string(name: String): String =
    this[name]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()

private fun JsonObject.stringOrNull(name: String): String? =
    string(name).takeIf(String::isNotBlank)

private fun JsonObject.int(name: String): Int? =
    this[name]?.jsonPrimitive?.intOrNull

private fun JsonObject.stringList(name: String): List<String> =
    (this[name] as? JsonArray)
        ?.mapNotNull { it.jsonPrimitive.contentOrNull?.trim()?.takeIf(String::isNotBlank) }
        .orEmpty()

private fun JsonObject.objectList(name: String): List<JsonObject> =
    (this[name] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

private val terminalWorkflowStatuses = setOf("succeeded", "partial", "failed", "cancelled")

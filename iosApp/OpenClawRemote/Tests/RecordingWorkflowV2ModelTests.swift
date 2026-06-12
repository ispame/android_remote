import Foundation

@main
struct RecordingWorkflowV2ModelTests {
    static func main() throws {
        let taskBase: [String: Any] = [
            "workflow_id": "workflow-1",
            "prompt": "Research",
            "depends_on": [],
            "completion_criteria": [],
            "risk": "normal",
            "replay_safety": "safe",
            "attempt": 1,
            "max_attempts": 2,
            "evidence": [],
            "artifacts": [],
            "created_at": "2026-06-11T05:46:00Z",
            "updated_at": "2026-06-11T05:47:00Z"
        ]
        var degraded = taskBase
        degraded.merge([
            "task_id": "spacex",
            "title": "SpaceX",
            "status": "degraded",
            "confidence": 0.72,
            "executor_hint": "hermes",
            "model_hint": "research-model",
            "source_constraints": ["official", "primary"],
            "available_actions": ["retry"],
            "warnings": ["Evidence was quarantined"]
        ]) { _, new in new }
        var failed = taskBase
        failed.merge([
            "task_id": "cxmt",
            "title": "CXMT",
            "status": "failed",
            "available_actions": ["retry", "skip"]
        ]) { _, new in new }
        var summary = taskBase
        summary.merge([
            "task_id": "summary",
            "system_kind": "summary",
            "title": "Summary",
            "status": "succeeded"
        ]) { _, new in new }

        let workflow = RecordingWorkflowSnapshot(json: [
            "workflow_id": "workflow-1",
            "account_id": "account-1",
            "backend_id": "backend-1",
            "recording_id": "recording-1",
            "title": "Research report",
            "status": "partial",
            "revision": 7,
            "quality_state": "completed_with_gaps",
            "warnings": ["CXMT premise is unverified"],
            "tasks": [degraded, failed, summary],
            "created_at": "2026-06-11T05:46:00Z",
            "updated_at": "2026-06-11T05:48:00Z"
        ])

        try require(workflow?.effectiveRevision == 7, "revision should parse")
        try require(workflow?.businessTaskCount == 2, "summary must not count as a business task")
        try require(workflow?.degradedTaskCount == 1, "degraded tasks need a distinct count")
        try require(workflow?.failedTaskCount == 1, "failed tasks need a distinct count")
        try require(workflow?.progress == 0.5, "only succeeded and degraded tasks count toward report progress")
        try require(workflow?.tasks[0].executorHint == "hermes", "executor hint should parse")
        try require(workflow?.tasks[0].modelHint == "research-model", "model hint should parse")
        try require(workflow?.tasks[0].sourceConstraints == ["official", "primary"], "source constraints should parse")
        print("RecordingWorkflowV2ModelTests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw NSError(domain: "RecordingWorkflowV2ModelTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }
}

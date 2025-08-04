# taskmanager

Taskmanager is a cross-platform Flutter desktop application for managing projects, tasks, and subtasks.

## Application Requirements

Links

- [Jira Configuration](docs/jira-configuration.md)
- [AI Setup](docs/ai-setup.md)
- [Workflow Examples](docs/workflow-examples.md)

### Overview

Cross‑platform Flutter desktop app for managing projects, tasks, and subtasks.

### Core Concepts

- **Projects**: professional or personal, each with summary, tech stack, and color coding.
- **Tasks**: high‑level work items (local or Jira).
- **Subtasks**: granular, AI‑digestible units; can be created manually or via AI expansion.
- **Schedule**: sidebar panel aggregating tasks from all projects.

### AI Features

- **AI Expand** converts a task into subtasks using OpenAI or Claude.
- Subtasks can be queued for an AI agent (e.g., Codex) to implement within the codebase.
- Agent receives project summary, subtask prompt, and relevant files.

### Workflow

Morning review → queue subtasks for AI → midday review for feedback → afternoon review for finalization.
Larger feedback becomes new subtasks; aim to minimize merge conflicts.

### Scheduling

AI‑managed ordering: prioritize blockers and quick wins, start long tasks early.
Users can add/remove tasks, expand tasks, and mark subtasks for AI directly in the schedule.

### Integration

Jira credentials loaded from api_keys.txt; issues fetched, updated, and deleted via JiraService.
Local persistence via JSON in the application documents directory.

### Future Extensions

Estimated durations, notifications, multi‑agent collaboration, and rich reporting.

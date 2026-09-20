---
name: linear
description: >-
  Linear project management (task creation, document management, issue tracking).
  Activates automatically when the user mentions keywords such as "task", "issue", "Linear",
  "ticket", "file a ticket", "document", "spec", etc.
  Can also be invoked manually with /linear.
---

# Linear Project Management Skill

Utilizes Linear MCP tools to perform project-level task and document management.

## Usage

### Fetching Context

Identify the target team and project dynamically each time:

1. Retrieve team list using `mcp__claude_ai_Linear__list_teams`.
2. Retrieve project list for the target team using `mcp__claude_ai_Linear__list_projects`.
3. If needed, retrieve details (including resources) using `mcp__claude_ai_Linear__get_project`.

If the user does not specify a project, present the list and ask them to select one.

### Task Management

#### List and Search

```
mcp__claude_ai_Linear__list_issues
  - project: Project name
  - assignee: "me" (assigned to self)
  - state: Filter by status name (e.g., "In Progress", "Todo")
  - query: Keyword search
```

#### Get Details

```
mcp__claude_ai_Linear__get_issue
  - id: Issue identifier (e.g., "PROJ-123")
  - includeRelations: true (to include related issues)
```

#### Create New Issue

Search existing issues with `list_issues` beforehand to avoid duplicates.

```
mcp__claude_ai_Linear__save_issue
  - title: Issue title (required)
  - team: Team name (required)
  - project: Project name
  - description: Written in Markdown
  - priority: 0=None, 1=Urgent, 2=High, 3=Normal, 4=Low
  - labels: Array of label names
  - assignee: "me" or username
```

Fetch valid statuses and labels beforehand:
- `mcp__claude_ai_Linear__list_issue_statuses` (specified by team)
- `mcp__claude_ai_Linear__list_issue_labels` (specified by team)

#### Update

```
mcp__claude_ai_Linear__save_issue
  - id: Issue identifier (e.g., "PROJ-123")
  - state: Target status name
  - assignee: Target assignee
  - priority: Target priority
  (specify only fields being updated)
```

#### Add Comment

```
mcp__claude_ai_Linear__save_comment
  - issueId: Issue identifier (e.g., "PROJ-123")
  - body: Written in Markdown
```

### Document Management

#### List and Search

```
mcp__claude_ai_Linear__list_documents
  - projectId: Project ID
  - query: Keyword search
```

#### Create New Document

Check existing documents with `list_documents` first to prevent duplicates.

```
mcp__claude_ai_Linear__create_document
  - title: Document title (required)
  - content: Written in Markdown
  - project: Project name
```

#### Update

```
mcp__claude_ai_Linear__update_document
  - id: Document ID (required)
  - content: Updated Markdown content
  - title: When changing title only
```

## Auto-Activation Guidelines

Automatically consult Linear without asking user confirmation under these conditions:

- User mentions "task", "ticket", or "issue".
- Linear project or issue is relevant to the current work context.
- User requests "file a ticket" or "open an issue".

When matching issues are found:
- Present a concise summary of issue title, status, and assignee.

When nothing matches:
- Continue silently (do not output a message stating nothing was found).

## Workflow Best Practices

- **Avoid Duplicates**: Search existing issues before creating tasks.
- **Markdown**: Always write description and content in Markdown.
- **Verify Statuses**: Fetch valid statuses via `list_issue_statuses` when creating or updating tasks.
- **Consistent Labels**: Check existing labels via `list_issue_labels` before creating new ones.
- **Link Projects**: Always associate tasks and documents with their corresponding project.

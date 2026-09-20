{{- $config := includeTemplate "private_dot_local/private_share/agent-config/agent-config.sample.json" . | fromJson -}}
{{- $role := index $config.agentRoles .agent -}}
---
name: {{ .agent }}
description: {{ $role.description | quote }}
{{- if eq $role.access "read" }}
tools: Read, Grep, Glob
{{- else }}
tools: Read, Write, Edit, Bash, Grep, Glob
{{- end }}
---

{{ includeTemplate (printf "agent-defs/prompts/%s.md" .agent) . }}

## Native role contract

- Read the role schema before returning structured output: `~/.agents/agent-defs/schemas/{{ .agent }}.json`.
- The schema and the role prompt are the source of truth. Do not choose a provider or model in this native path.

{{- $tiers := includeTemplate "agent-defs/tiers.json" . | fromJson -}}
{{- $manifests := includeTemplate "agent-defs/manifests.json" . | fromJson -}}
{{- $m := index $manifests .agent -}}
{{- $t := index $tiers $m.tier "opencode" -}}
---
description: {{ $m.description | quote }}
mode: subagent
model: {{ $t.model }}
reasoningEffort: {{ $t.effort }}
{{ if eq $m.access "read" }}permission:
  edit: deny
  bash: deny
{{ end }}---

{{ includeTemplate (printf "agent-defs/prompts/%s.md" .agent) . }}

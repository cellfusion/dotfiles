{{- $tiers := includeTemplate "agent-defs/tiers.json" . | fromJson -}}
{{- $manifests := includeTemplate "agent-defs/manifests.json" . | fromJson -}}
{{- $legacyManifests := includeTemplate "agent-defs/legacy-agent-manifests.json" . | fromJson -}}
{{- $m := index $manifests .agent -}}
{{- if not $m }}{{- $m = index $legacyManifests .agent -}}{{- end -}}
{{- $t := index $tiers $m.tier "claude" -}}
---
name: {{ .agent }}
description: {{ $m.description | quote }}
model: {{ $t.model }}
effort: {{ $t.effort }}
{{ if eq $m.access "read" }}tools: Read, Grep, Glob
{{ end }}---

{{ includeTemplate (printf "agent-defs/prompts/%s.md" .agent) . }}

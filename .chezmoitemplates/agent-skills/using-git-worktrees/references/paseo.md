# Paseo: Known Unsupported Environment

`pr-review --environment paseo <PR>` recognizes the environment name but reports
`unsupported-environment` before creating any run directory, checkout, workspace, pane or session.
This is not operational Paseo support. Current CLI/guide, safe hook suppression, private launch,
live identity, readiness, receipt semantics and owner-aware cleanup have not been verified.

Do not reuse removed review plugins/transports, invent commands or IDs, assume Orca/Herdr
compatibility, install a legacy transport, or silently fall back to another environment. Preserve
existing user resources. A future implementation requires verified current interfaces and explicit
capability evidence before resource creation; this reference does not authorize that work.

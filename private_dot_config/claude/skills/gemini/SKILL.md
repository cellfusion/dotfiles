---
name: gemini
description: >-
  Guidance for leveraging tasks where Gemini excels. Use when the user requests or asks about
  massive context processing, multimodal analysis, Google ecosystem integrations,
  codebase-wide cross-cutting analysis, or video/audio processing.
---

# Gemini Usage Guide

Guidance covering the domains where Gemini excels and how to leverage them effectively.
By appropriately dividing responsibilities between Claude and Gemini, development becomes significantly more efficient.

## Areas Where Gemini Excels

### 1. Large-Context Processing (Over 1M Tokens)

- Capable of processing massive documents, log files, and large codebases simultaneously.
- Excels at cross-cutting analysis spanning multiple files.
- **Examples**: Analyzing huge log files, summarizing extensive specifications, analyzing large test suites.

### 2. Multimodal Analysis (Images, Video, Audio)

- Understanding and summarizing video content (including YouTube videos).
- Transcribing and analyzing audio files.
- Optical character recognition and chart/diagram analysis in images.
- **Examples**: Summarizing tech conference videos, screencast analysis, generating meeting minutes from recordings.

### 3. Google Ecosystem Integrations

- Real-time grounding via Google Search integration.
- Integration with Google Workspace (Docs, Sheets, Slides).
- Integration with Google services such as Google Maps and YouTube.
- **Examples**: Researching latest tech trends, analyzing and summarizing Google Docs.

### 4. Cross-Cutting Codebase Analysis

- High-level dependency analysis across an entire repository.
- Scope-of-impact analysis for large-scale refactorings.
- Architecture-level code reviews.
- **Examples**: Mapping monorepo dependencies, crafting legacy migration plans.

### 5. Multilingual Processing

- Broad language support and translation.
- Batch processing of multilingual content.
- **Examples**: Translating multilingual documentation, internationalization (i18n) support.

## Use-Case Guide

### Document and Log Analysis

When handling large volumes of text data, take advantage of Gemini's extensive context window:

1. Provide target files to Gemini.
2. Specify concrete analytical criteria (e.g., error pattern extraction, bottleneck identification).
3. Request output in a structured format.

### Video and Audio Processing

1. Provide YouTube URLs or media files to Gemini.
2. Clarify the objective (summary, transcription, specific information extraction).
3. Request timestamped outputs for easier downstream reference.

### Codebase-Wide Analysis

1. Provide key repository files to Gemini as a batch.
2. Request an architectural overview or visualization of dependencies.
3. Request reviews focused on specific aspects (security, performance, design patterns).

## Claude vs. Gemini Division of Labor

| Task | Recommended Tool | Rationale |
|---|---|---|
| Bulk file/log analysis | **Gemini** | Excels at large context windows |
| Video and audio analysis | **Gemini** | Native multimodal capability |
| Google service integrations | **Gemini** | Native ecosystem integration |
| Code implementation and fixes | **Claude** | High coding precision |
| Complex reasoning and analysis | **Claude** | Excels at logical reasoning |
| File editing and Git operations | **Claude** | Rich tool integration |
| Security reviews | **Both** | In-depth review with Claude; broad scan with Gemini |
| Refactoring planning | **Gemini -> Claude** | Impact analysis in Gemini; implementation in Claude |

### Combination Patterns

- **Research -> Implementation**: Broad research and analysis via Gemini -> Concrete implementation via Claude.
- **Review**: High-level repository architecture review via Gemini -> Detailed per-file review via Claude.
- **Video Learning -> Code**: Summarize technical video via Gemini -> Translate insights into code via Claude.

# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "sentence-transformers>=3.0.0",
#     "numpy",
#     "sudachipy>=0.6.8",
#     "sudachidict-core>=20240409",
# ]
# ///
"""Experimental, opt-in document-level embedding metrics.

This separate entry point depends on torch and sentence-transformers. Loading
the default model may download approximately 1 GB; run only with authorization.
Normalized embeddings measure adjacent-sentence similarity range, minimum
adjacent similarity, and maximum non-adjacent similarity. These are topic and
repetition review hints, not authorship detection or a naturalness score.

Imported thresholds are historical corpus estimates, not validated guarantees
for the current document, genre, or installation. Custom models produce metrics
only: thresholds from the default model cannot be transferred to them.
Remote model-repository Python is disabled by default. Enabling
``--trust-remote-code`` requires explicit approval to execute that code,
separately from approval to download model files.

Usage: uv run scripts/semantic.py <file.md> [--json] [--genre essay|tech|business]
Findings exit 0; input/model failures exit 1; invalid arguments exit 2.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from textcore import (
    Finding,
    iter_lines_with_no,
    mask_markdown_structure,
    read_source_file,
    split_sentences_with_lines,
)

DEFAULT_MODEL = "cl-nagoya/ruri-v3-310m"

# 短文書ガード。統計的な起伏・反復の測定は文数が少ないと意味をなさない
# （lint.py の低分散検出器などが短文書を除外するのと同じ哲学）。
# コーパス実験（sweep.py）は「n>=3で計算可、n>=2でvar/range計算」という緩い下限だったが、
# 実運用の目安としては最低10文程度なければ「起伏がない」という判定自体が
# 統計的に不安定（1〜2箇所の類似度でrange/varがほぼ決まってしまう）と判断し、
# 10文未満はここで打ち切る。
MIN_SENTENCES_FOR_STATS = 10

# Historical default-model thresholds retained as experimental review hints.
# The original corpus and calibration reports are not bundled with this skill;
# do not present their claimed detection rates as verified evidence.
DEFAULT_FLATNESS_THRESHOLD = 0.16122889518737793

GENRE_PROFILES: dict[str, dict] = {
    "essay": {
        "flatness_threshold": 0.15813499689102173,
        "flatness_calibration": "historical essay threshold; not independently validated",
    },
    "tech": {
        "flatness_threshold": 0.14261949062347412,
        "flatness_calibration": "historical tech threshold; not independently validated",
    },
    "business": {
        "flatness_threshold": 0.15565699338912964,
        "flatness_calibration": "historical business threshold; not independently validated",
    },
}

# Reference thresholds describe metrics, not defects or author identity.
SEMANTIC_REPETITION_MAX_THRESHOLD = 0.9322158694267273
TOPIC_JUMP_MIN_THRESHOLD = 0.765757143497467


def doc_sentences_with_lines(raw_text: str) -> list[tuple[int, str]]:
    """Return visible prose sentences and source line numbers for embedding."""
    masked = mask_markdown_structure(raw_text)
    lines = iter_lines_with_no(masked)
    raw_lines_by_no = dict(iter_lines_with_no(raw_text))
    sentences = split_sentences_with_lines(lines, raw_lines_by_no)
    out = []
    for no, masked_s, _ in sentences:
        s = masked_s.strip()
        if s:
            out.append((no, s))
    return out


_model_cache = {}


def load_model(model_name: str, *, trust_remote_code: bool = False):
    """Load once per model/trust policy; repository Python needs explicit opt-in."""
    cache_key = (model_name, trust_remote_code)
    if cache_key in _model_cache:
        return _model_cache[cache_key]

    print(
        f"[semantic.py] Loading model: {model_name}. "
        "The first load may download about 1 GB from Hugging Face; "
        "offline use requires a complete local cache.",
        file=sys.stderr,
    )
    if trust_remote_code:
        print(
            "[semantic.py] Remote-code trust enabled: model-repository Python may execute.",
            file=sys.stderr,
        )
    import torch
    from sentence_transformers import SentenceTransformer

    device = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")
    model = SentenceTransformer(model_name, device=device, trust_remote_code=trust_remote_code)
    _model_cache[cache_key] = model
    return model


def compute_metrics(embeddings) -> dict:
    """Compute cosine similarity metrics from normalized embedding rows."""
    import numpy as np

    n = embeddings.shape[0]
    out = {
        "semantic_repetition_max": None,
        "coherence_flatness_range": None,
        "topic_jump_min": None,
    }
    if n < 3:
        return out
    sim = embeddings @ embeddings.T

    adj = np.array([sim[i, i + 1] for i in range(n - 1)])
    if len(adj) >= 2:
        out["coherence_flatness_range"] = float(adj.max() - adj.min())
        out["topic_jump_min"] = float(adj.min())
    elif len(adj) == 1:
        out["topic_jump_min"] = float(adj[0])

    iu = np.triu_indices(n, k=2)
    non_adj = sim[iu]
    if non_adj.size:
        out["semantic_repetition_max"] = float(non_adj.max())

    return out


def run_semantic(
    raw_text: str, genre: str | None = None, model_name: str = DEFAULT_MODEL,
    *, trust_remote_code: bool = False,
) -> tuple[list[Finding], dict]:
    profile = GENRE_PROFILES.get(genre, {})
    flatness_threshold = (
        profile.get("flatness_threshold", DEFAULT_FLATNESS_THRESHOLD)
        if model_name == DEFAULT_MODEL else None
    )
    flatness_calibration = profile.get(
        "flatness_calibration", "historical shared threshold; not independently validated"
    )

    sentence_items = doc_sentences_with_lines(raw_text)
    n_sentences = len(sentence_items)

    stats: dict = {
        "genre": genre,
        "n_sentences": n_sentences,
        "model": model_name,
        "flatness_threshold": flatness_threshold,
        "metrics": None,
        "skipped": False,
        "skip_reason": None,
    }

    if n_sentences < MIN_SENTENCES_FOR_STATS:
        stats["skipped"] = True
        stats["skip_reason"] = (
            f"Only {n_sentences} prose sentences; at least "
            f"{MIN_SENTENCES_FOR_STATS} are required for these experimental metrics."
        )
        return [], stats

    lines_no = [no for no, _ in sentence_items]
    sentences = [s for _, s in sentence_items]

    model = load_model(model_name, trust_remote_code=trust_remote_code)
    embeddings = model.encode(
        sentences, convert_to_numpy=True, show_progress_bar=False, normalize_embeddings=True
    )
    metrics = compute_metrics(embeddings)
    stats["metrics"] = metrics

    if flatness_threshold is None:
        stats["skip_reason"] = (
            "Custom model: metrics only; default-model thresholds are inapplicable."
        )
        print(f"[semantic.py] {stats['skip_reason']}", file=sys.stderr)
        return [], stats

    findings: list[Finding] = []

    cfr = metrics.get("coherence_flatness_range")
    if cfr is not None and cfr <= flatness_threshold:
        # レポート対象行はとりあえず文書冒頭（文単位ではなく文書全体集計の検出器なので、
        # lint.py の antithesis_repetition 等の「文書全体集計型」の扱いに倣う）。
        line = lines_no[0] if lines_no else 1
        findings.append(
            Finding(
                line=line,
                category="semantic_topic_flatness",
                excerpt=f"隣接文類似度レンジ={cfr:.4f}（閾値{flatness_threshold:.4f}以下）",
                severity="warn",  # 実験的検出器のため critical にはしない
                detail=(
                    "Adjacent sentence similarities have a narrow range. Check whether "
                    "the document needs clearer topic progression; consistent focus may "
                    "be appropriate for its genre. Do not add digressions merely to vary "
                    f"this metric. EXPERIMENTAL: {flatness_calibration}. "
                    "This does not identify authorship or establish a writing defect."
                ),
            )
        )

    srm = metrics.get("semantic_repetition_max")
    if srm is not None and srm <= SEMANTIC_REPETITION_MAX_THRESHOLD:
        line = lines_no[0] if lines_no else 1
        findings.append(
            Finding(
                line=line,
                category="semantic_repetition_max",
                excerpt=f"非隣接文ペア類似度max={srm:.4f}（参考閾値{SEMANTIC_REPETITION_MAX_THRESHOLD:.4f}以下）",
                severity="info",
                detail=(
                    "Reference metric: the most similar non-adjacent pair falls below "
                    "a historical threshold. Low repetition is not inherently a defect; "
                    "do not add paraphrases to change the metric. This is not evidence "
                    "of author identity or overall writing quality."
                ),
            )
        )

    tjm = metrics.get("topic_jump_min")
    if tjm is not None and tjm >= TOPIC_JUMP_MIN_THRESHOLD:
        line = lines_no[0] if lines_no else 1
        findings.append(
            Finding(
                line=line,
                category="topic_jump_min",
                excerpt=f"隣接文類似度最小値={tjm:.4f}（参考閾値{TOPIC_JUMP_MIN_THRESHOLD:.4f}以上）",
                severity="info",
                detail=(
                    "Reference metric: even the least-similar adjacent pair has high "
                    "similarity. Consistent topic focus may be desirable. This does not "
                    "establish excessive repetition, poor transitions, or authorship."
                ),
            )
        )

    return findings, stats


SEVERITY_LABEL = {"info": "情報", "warn": "警告", "critical": "重大"}


def print_human_report(path: Path, findings: list[Finding], stats: dict) -> None:
    print(f"=== semantic.py (EXPERIMENTAL): {path} ===")
    print(f"文数: {stats['n_sentences']}  モデル: {stats['model']}  genre: {stats['genre'] or '(未指定)'}")
    if stats["skipped"]:
        print(f"スキップ: {stats['skip_reason']}")
        return
    print(f"検出件数: {len(findings)}")
    if stats["skip_reason"]:
        print(f"Note: {stats['skip_reason']}")
    print()
    if not findings:
        print("検出なし。")
        return
    for f in findings:
        label = SEVERITY_LABEL.get(f.severity, f.severity)
        print(f"[{label}] L{f.line} ({f.category})")
        print(f"    該当箇所: {f.excerpt}")
        if f.detail:
            print(f"    詳細    : {f.detail}")
        print()


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "EXPERIMENTAL: topic-similarity review metrics, not authorship detection. "
            "Opt-in; torch/sentence-transformers; first load may download about 1 GB."
        )
    )
    parser.add_argument("file", type=Path, help="Markdown or UTF-8 text file to inspect")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    parser.add_argument(
        "--genre",
        choices=sorted(GENRE_PROFILES),
        default=None,
        help="Historical threshold profile (essay/tech/business); no quality guarantee",
    )
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Embedding model (default: {DEFAULT_MODEL}); custom models emit metrics only")
    parser.add_argument(
        "--trust-remote-code",
        action="store_true",
        help=(
            "Allow execution of Python from the selected model repository (default: "
            "disabled). Requires explicit approval independently of model downloads."
        ),
    )
    args = parser.parse_args()

    text, err = read_source_file(args.file)
    if err is not None:
        print(err, file=sys.stderr)
        return 1

    try:
        findings, stats = run_semantic(
            text, genre=args.genre, model_name=args.model,
            trust_remote_code=args.trust_remote_code,
        )
    except Exception as exc:
        print(
            f"Error: semantic model loading or inference failed: {exc}",
            file=sys.stderr,
        )
        if not args.trust_remote_code:
            print(
                "Remote model-repository Python is disabled. If the model requires it, "
                "obtain explicit approval before rerunning with --trust-remote-code; "
                "do not enable trust to suppress unrelated loading errors.",
                file=sys.stderr,
            )
        return 1

    if args.json:
        output = {
            "file": str(args.file),
            "stats": stats,
            "findings": [f.to_dict() for f in findings],
        }
        print(json.dumps(output, ensure_ascii=False, indent=2))
    else:
        print_human_report(args.file, findings, stats)

    # lint.py と同じ規律: 文章の中身に関する判定は exit 0（件数に関わらず）。
    return 0


if __name__ == "__main__":
    sys.exit(main())

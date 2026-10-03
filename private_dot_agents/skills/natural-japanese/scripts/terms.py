# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "sudachipy>=0.6.8",
#     "sudachidict-core>=20240409",
# ]
# ///
"""Extract candidate katakana terms, ASCII acronyms, and proper names.

Candidates are sorted by their first visible occurrence. ``has_gloss_hint``
means only that an explanation marker occurs nearby, not that a term is defined
or needs a definition. Headings and prose are included; code, comments, front
matter, lists, quotes, and tables are excluded.

Usage: uv run scripts/terms.py <file.md> [--json]
Findings exit 0; unreadable input exits 1; invalid CLI arguments exit 2.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from textcore import (
    _HEADING_RE,
    _heading_level_and_text,
    get_tokenizer,
    iter_lines_with_no,
    mask_markdown_structure,
    read_source_file,
)

# ---------------------------------------------------------------------------
# --terms（用語インベントリ）
#
# sudachipy の解析結果から、専門用語候補（カタカナ複合語・ASCII英略語・
# 固有名詞らしき語）を機械的に列挙する。有用な専門用語かどうか、初出で
# 説明済みかどうかの判断は行わない（has_gloss_hint はあくまでヒント）。
# 文体憲法第4条（初出で説明すべき用語）の確認材料として AI に渡す素材。
# ---------------------------------------------------------------------------

_KATAKANA_CHAR_RE = re.compile(r"^[ァ-ヶー]+$")
# Python の \b は Unicode 単語境界を使うため、日本語の文字（漢字・かな）は
# 単語文字として扱われ、「APIとは」のように直後に日本語が続くと \b が成立せず
# マッチしない。ASCII の英数字が前後に隣接していない（＝英略語として孤立している）
# ことだけを見ればよいので、\b の代わりに明示的な否定先読み/後読みで判定する
# （直前直後が日本語であることは許容し、直前直後が別の ASCII 英数字であることのみ排除）。
_ASCII_ACRONYM_RE = re.compile(r"(?<![A-Za-z0-9])[A-Z]{2,}[0-9]*(?![A-Za-z0-9])")
TERMS_KATAKANA_MIN_LEN = 3
TERMS_GLOSS_CONTEXT_CHARS = 80
TERMS_GLOSS_MARKER_WORDS = ["とは", "と呼ぶ", "という", "、つまり"]


def _is_katakana_token(surface: str) -> bool:
    return bool(_KATAKANA_CHAR_RE.match(surface))


# 英字が先頭大文字で残りが英数字（"Cloudflare" "TypeScript" 等）の語。
# sudachipy の辞書は未登録の製品名/固有名詞をしばしば「名詞,普通名詞」に倒す
# （固有名詞タグに乗らない）ため、POS だけに頼ると製品名を取りこぼす。
# 表層の形（先頭大文字+英数字）という単純なヒューリスティクスで補う
# （除外辞書は作らない方針のため、あくまで形のみで判定する）。
_CAPITALIZED_LATIN_WORD_RE = re.compile(r"^[A-Z][a-zA-Z0-9]*$")


def _is_proper_noun_or_capitalized_latin_morpheme(morpheme) -> bool:
    pos = morpheme.part_of_speech()
    if pos[0] == "名詞" and pos[1] == "固有名詞":
        return True
    surface = morpheme.surface()
    return len(surface) >= 2 and bool(_CAPITALIZED_LATIN_WORD_RE.match(surface))


def _term_context_and_gloss_hint(
    term: str, first_line_no: int, first_offset: int,
    search_text: str, line_offsets: dict[int, int]
) -> tuple[str, bool]:
    """Return visible context and nearby gloss markers at the detected offset."""
    local_idx = first_offset

    abs_pos = line_offsets.get(first_line_no, 0) + local_idx
    ctx_start = max(0, abs_pos - TERMS_GLOSS_CONTEXT_CHARS)
    ctx_end = abs_pos + len(term) + TERMS_GLOSS_CONTEXT_CHARS
    context = search_text[ctx_start:ctx_end]

    term_start_local = abs_pos - ctx_start
    term_end_local = term_start_local + len(term)
    after = context[term_end_local : term_end_local + 2]
    has_gloss_hint = after.startswith("(") or after.startswith("（")
    if not has_gloss_hint:
        has_gloss_hint = any(marker in context for marker in TERMS_GLOSS_MARKER_WORDS)

    return context.strip(), has_gloss_hint


def build_term_inventory(raw_text: str) -> list[dict]:
    """Extract review candidates, not verdicts about jargon or definitions."""
    tokenizer = get_tokenizer()
    from sudachipy import SplitMode

    visible_text = mask_markdown_structure(raw_text, preserve_structure=True)
    masked_structure = mask_markdown_structure(raw_text)
    body_lines = iter_lines_with_no(masked_structure)

    # Recover only visible headings, never heading-like code or front matter.
    heading_lines: list[tuple[int, str]] = []
    for no, line in iter_lines_with_no(visible_text):
        if _HEADING_RE.match(line):
            _, heading_text = _heading_level_and_text(line)
            heading_offset = line.find(heading_text) if heading_text else len(line)
            heading_lines.append((no, " " * heading_offset + heading_text))

    combined_lines = sorted(body_lines + heading_lines, key=lambda t: t[0])
    visible_lines = dict(combined_lines)
    visible_text = "\n".join(
        visible_lines.get(no, " " * len(line)).ljust(len(line))
        for no, line in enumerate(raw_text.split("\n"), start=1)
    )

    # Structural masking retains original offsets for context extraction.
    line_offsets: dict[int, int] = {}
    pos = 0
    for no, line_text in enumerate(visible_text.split("\n"), start=1):
        line_offsets[no] = pos
        pos += len(line_text) + 1

    # Each candidate records distinct detected spans, not substring counts.
    # Multiple extraction passes can discover the same span; count it once.
    seen: dict[str, dict] = {}

    def register(term: str, no: int, offset: int) -> None:
        term = term.strip()
        if not term:
            return
        position = (no, offset)
        if term not in seen:
            seen[term] = {"first_line": no, "first_offset": offset, "positions": set()}
        info = seen[term]
        info["positions"].add(position)
        if position < (info["first_line"], info["first_offset"]):
            info["first_line"], info["first_offset"] = position

    for no, line in combined_lines:
        if not line.strip():
            continue

        # (b) ASCII英略語（大文字2文字以上）は表層の正規表現で拾う
        for m in _ASCII_ACRONYM_RE.finditer(line):
            register(m.group(0), no, m.start())

        # (a) カタカナ複合語 / (c) 固有名詞・製品名らしき語（sudachiのPOSが固有名詞、
        # または先頭大文字の英単語=製品名によくある表層形）は形態素解析で連続する
        # 同種の形態素をまとめて1つの候補語にする（元のスパンをそのまま使い、
        # 語間の空白等も保持する）。
        morphemes = list(tokenizer.tokenize(line, SplitMode.C))
        i = 0
        n = len(morphemes)
        while i < n:
            m0 = morphemes[i]
            if _is_katakana_token(m0.surface()):
                j = i + 1
                while j < n and _is_katakana_token(morphemes[j].surface()):
                    j += 1
                span_start = m0.begin()
                span_end = morphemes[j - 1].end()
                term = line[span_start:span_end]
                if len(term) >= TERMS_KATAKANA_MIN_LEN:
                    register(term, no, span_start)
                i = j
                continue
            if _is_proper_noun_or_capitalized_latin_morpheme(m0):
                j = i + 1
                while j < n and _is_proper_noun_or_capitalized_latin_morpheme(morphemes[j]):
                    j += 1
                span_start = m0.begin()
                span_end = morphemes[j - 1].end()
                term = line[span_start:span_end]
                register(term, no, span_start)
                i = j
                continue
            i += 1

    results = []
    for term, info in seen.items():
        count = len(info["positions"])
        context, has_gloss_hint = _term_context_and_gloss_hint(
            term, info["first_line"], info["first_offset"], visible_text, line_offsets
        )
        results.append(
            {
                "term": term,
                "first_line": info["first_line"],
                "count": count,
                "has_gloss_hint": has_gloss_hint,
                "context": context,
            }
        )

    # 初出順（文書内の実際の出現位置＝(first_line, first_offset) の昇順）。
    # first_offset は出力スキーマに含めない内部情報なので、seen から引いてソートキーに使う。
    results.sort(key=lambda r: (r["first_line"], seen[r["term"]]["first_offset"]))
    return results


def print_terms_human(path: Path, terms: list[dict]) -> None:
    print(f"=== terms: {path} ===")
    print(
        "Candidates and nearby gloss markers are review hints, not proof that "
        "a term is undefined or that its use is inappropriate."
    )
    print()
    if not terms:
        print("(用語候補なし)")
        return
    for t in terms:
        hint = "あり" if t["has_gloss_hint"] else "なし"
        print(f"L{t['first_line']} {t['term']} (出現{t['count']}回, 説明手掛かり: {hint})")
        print(f"    近傍: {t['context']}")
        print()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="List candidate terms in first-occurrence order; review hints, not a CI gate."
    )
    parser.add_argument("file", type=Path, help="Markdown or UTF-8 text file to inspect")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    args = parser.parse_args()

    # 「文章の中身に関する判断」と「そもそも実行できない入力エラー」は区別する。
    # 前者（抽出結果）は exit 0、後者（ファイル不在/ディレクトリ指定/読み取り不可等）は exit 1。
    text, err = read_source_file(args.file)
    if err is not None:
        print(err, file=sys.stderr)
        return 1

    terms = build_term_inventory(text)
    if args.json:
        print(json.dumps({"terms": terms}, ensure_ascii=False, indent=2))
    else:
        print_terms_human(args.file, terms)
    return 0


if __name__ == "__main__":
    sys.exit(main())


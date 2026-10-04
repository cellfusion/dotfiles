# /// script
# requires-python = ">=3.10"
# dependencies = ["sudachipy>=0.6.8", "sudachidict-core>=20240409"]
# ///
"""Behavioral regressions; no embedding model or network is required."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.dont_write_bytecode = True

SCRIPTS = Path(sys.argv.pop(1)).resolve()
sys.path.insert(0, str(SCRIPTS))
import calibrate
import lint
import outline
import semantic
import terms
import textcore


class ScriptRegressions(unittest.TestCase):
    def test_terms_exclude_hidden_headings_and_substring_counts(self):
        source = "---\n# XML\n---\n```python\n# SQL\n```\n# API\nAPIとAPIKEY。`API`はコード。\nCloudflareとSDKを使う。\n"
        inventory = terms.build_term_inventory(source)
        by_term = {item["term"]: item for item in inventory}
        self.assertNotIn("XML", by_term)
        self.assertNotIn("SQL", by_term)
        self.assertEqual(by_term["API"]["first_line"], 7)
        self.assertEqual(by_term["API"]["count"], 2)
        self.assertEqual(by_term["APIKEY"]["count"], 1)
        self.assertEqual(by_term["SDK"]["count"], 1)
        self.assertNotIn("XML", by_term["API"]["context"])
        self.assertNotIn("SQL", by_term["API"]["context"])
        self.assertNotIn("`API`", by_term["API"]["context"])

    def test_terms_preserve_mixed_same_line_first_occurrence_order(self):
        inventory = terms.build_term_inventory("CloudflareとSDKとプラットフォームを使う。")
        names = [item["term"] for item in inventory]
        self.assertLess(names.index("Cloudflare"), names.index("SDK"))
        self.assertLess(names.index("SDK"), names.index("プラットフォーム"))

    def test_hidden_explanation_markers_do_not_supply_gloss_hints(self):
        inventory = terms.build_term_inventory("APIを使う。`とは`\n<!-- APIという説明 -->\n")
        api = next(item for item in inventory if item["term"] == "API")
        self.assertEqual(api["count"], 1)
        self.assertFalse(api["has_gloss_hint"])

    def test_fence_inside_comment_does_not_hide_following_prose(self):
        source = "<!--\n```\n-->\n重要なのは確認です。\n"
        masked = textcore.mask_markdown_structure(source)
        self.assertIn("重要なのは確認です。", masked)
        findings = lint.detect_forbidden_phrases(textcore.iter_lines_with_no(masked))
        self.assertEqual([item.line for item in findings], [4])

    def test_comment_marker_inside_fence_does_not_hide_following_terms(self):
        source = "```html\n<!--\n```\nAPIを使う。\n"
        inventory = terms.build_term_inventory(source)
        api = next(item for item in inventory if item["term"] == "API")
        self.assertEqual(api["first_line"], 4)
        self.assertEqual(api["count"], 1)

    def test_inline_comment_marker_in_code_does_not_hide_following_terms(self):
        inventory = terms.build_term_inventory("`<!--` APIを使う。")
        api = next(item for item in inventory if item["term"] == "API")
        self.assertEqual(api["count"], 1)

    def test_outline_preserves_prose_after_comment_marker_in_fence(self):
        entries = outline.build_outline("```html\n<!--\n```\n本文です。\n")
        self.assertEqual(entries, [{"line": 4, "kind": "lead", "level": None, "text": "本文です。"}])

    def test_semantic_embeddings_receive_visible_prose_only(self):
        items = semantic.doc_sentences_with_lines("本文`SECRET`です<!-- HIDDEN -->。\n# TITLE\n")
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0][0], 1)
        self.assertIn("本文", items[0][1])
        self.assertNotIn("SECRET", items[0][1])
        self.assertNotIn("HIDDEN", items[0][1])
        self.assertNotIn("TITLE", items[0][1])

    def test_backticks_inside_comments_cannot_expose_later_comments(self):
        for source in ("<!-- ` -->本文<!-- SECRET ` -->。",
                       "<!--\n` -->本文<!-- SECRET ` -->。"):
            with self.subTest(source=source):
                masked = textcore.mask_markdown_structure(source)
                self.assertIn("本文", masked)
                self.assertNotIn("SECRET", masked)
                sentences = semantic.doc_sentences_with_lines(source)
                self.assertTrue(any("本文" in sentence for _, sentence in sentences))
                self.assertTrue(all("SECRET" not in sentence for _, sentence in sentences))

    def test_short_semantic_documents_do_not_load_models(self):
        findings, stats = semantic.run_semantic("本文です。")
        self.assertEqual(findings, [])
        self.assertTrue(stats["skipped"])
        self.assertIsNone(stats["metrics"])

    def test_experimental_structure_ignores_code_and_front_matter(self):
        source = "---\n# まとめ\n---\n```\n# まとめ\n**a** **b** **c**\nフェーズ1 フェーズ2 フェーズ3\n✅✅✅\n```\n本文。\n"
        findings, stats = lint.detect_structural_ai_habits(source)
        self.assertEqual(findings, [])
        for key in ("bold_span_count", "boilerplate_heading_count", "numbered_phase_hit_count", "emoji_symbol_count"):
            self.assertEqual(stats[key], 0, key)

    def test_nominal_aggregate_persists_after_count_changes(self):
        previous = textcore.Finding(3, "nominal_ending", "体言止め0件（全5文、約2000字）", "info")
        current = textcore.Finding(5, "nominal_ending", "体言止め0件（全6文、約2200字）", "info")
        resolved, summary = lint.compute_baseline_diff([current], {"findings": [previous.to_dict()]})
        self.assertEqual(resolved, [])
        self.assertEqual(summary, {"new": 0, "persisting": 1, "resolved": 0})

    def test_calibration_rejects_missing_or_empty_corpus(self):
        original = calibrate.CORPUS_DIR
        try:
            with tempfile.TemporaryDirectory() as temporary:
                calibrate.CORPUS_DIR = Path(temporary) / "missing"
                with self.assertRaises(ValueError):
                    calibrate.load_corpus()
                calibrate.CORPUS_DIR.mkdir()
                with self.assertRaises(ValueError):
                    calibrate.load_corpus()
        finally:
            calibrate.CORPUS_DIR = original

    def test_calibration_does_not_recommend_without_ai_samples(self):
        original_corpus, original_reports = calibrate.CORPUS_DIR, calibrate.REPORTS_DIR
        try:
            with tempfile.TemporaryDirectory() as temporary:
                calibrate.CORPUS_DIR = Path(temporary)
                calibrate.REPORTS_DIR = Path(temporary) / "reports"
                directory = Path(temporary) / "human/web"
                directory.mkdir(parents=True)
                (directory / "sample.txt").write_text("本文です。", encoding="utf-8")
                with contextlib.redirect_stdout(io.StringIO()):
                    calibrate.cmd_sweep(lint, "low_sentence_variance")
                report = json.loads((calibrate.REPORTS_DIR / "sweep_low_sentence_variance.json").read_text(encoding="utf-8"))
                self.assertEqual(report["n_ai"], 0)
                self.assertIsNone(report["recommended"])
        finally:
            calibrate.CORPUS_DIR, calibrate.REPORTS_DIR = original_corpus, original_reports


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ScriptRegressions))
    print(f"SUMMARY {result.testsRun} {len(result.failures) + len(result.errors)}")
    sys.exit(0 if result.wasSuccessful() else 1)

# Reports: make findings and their limits understandable

## Purpose

A report explains what was investigated, what the evidence shows, and what it does not show. Some reports support decisions; others are descriptive records. Do not force every report to recommend an action.

**Source guidance:** The [2022 public-writing recommendation](../sources.md) supports accuracy, clear main points, useful headings, and reader-oriented structure. The reporting checklist and examples below are editorial heuristics, not an official mandatory format.

## Information readers may need

- Purpose, question, scope, and exclusions.
- Main findings, with relevant numbers and units.
- Data source, time period, population, and definitions.
- Method, including exclusions or transformations needed to interpret or reproduce the findings.
- Limitations and uncertainty near affected claims.
- Interpretations or recommendations, clearly distinguished and only when supported or requested.

Use the level of detail appropriate to the report. An executive brief may link to a detailed method; a research report may need it in full. Do not claim reproducibility when queries, source data, or parameters are unavailable.

## Structure

Put a supported main finding or summary early when readers need quick orientation, then supply evidence and method. Preserve a chronological arrangement when the investigation itself is the subject. Technical details can appear in an appendix if readers can find them.

A follow-up report should identify relevant changes in period, method, definitions, or prior findings. Describe an actual correction when supplied; do not invent a past error or reconciliation merely to make the report seem transparent.

Use stable tables and parallel language for genuine comparisons. Allocate explanation to important or difficult findings, but do not make ordinary segments artificially brief or invent anomalies to introduce variation.

## Quantitative fidelity

Keep counts, percentages, percentage points, ratios, denominators, periods, units, precision, and population boundaries distinct. Do not replace a count of visits with a count of people. Do not call a purchase rate a retention rate.

Derived quantities require a known basis:

- 「継続率4%」 does not necessarily imply 「96%が離脱」 if unobserved, pending, or ineligible cases exist.
- A rate of 4.6% is 2.3 times a 2.0% baseline only when that baseline is actually supplied and definitions are comparable.
- A single month-on-month decline does not establish a two-month trend.
- Chronological correlation does not establish the cause of a decline.
- A subgroup rate alone does not establish its contribution to an overall change.

Explain supported implications in plain language, but do not add a calculation, comparison, or causal interpretation that the material cannot justify. Put necessary caveats beside the number or summary they qualify, not only at the end.

## Distinguishing kinds of claims

Use attribution or structure to separate measured results, source reports, interpretations, forecasts, and proposals. Preserve 「推定」「可能性」「未確認」 and the same degree of confidence. A confident conclusion cannot be created from uncertain source data merely to make the summary decisive.

If a requested recommendation cannot be supported, state what remains unknown or what evidence is needed. Do not add an implementation plan, priority ranking, or personal conviction not present in the source or authorized by the task.

## Illustrative fictional sample

This self-contained example uses fictional data; it is not evidence for any real website.

```text
# そらマルシェ 流入経路調査（2026年6月）

## 主要結果
6月の総訪問数は128,400件で、前月比3%減だった。
検索流入は71,200件で、前月比8%減だった。
SNS経由の購入率は4.6%だった。

## 集計条件
期間は2026年6月1日から6月30日まで。
総訪問数と検索流入は、社内アクセスを除いたセッション数。
購入率は、対象セッションのうち購入に至った割合。

## 限界
流入経路ごとの増減が総訪問数の変化に与えた寄与は、
この集計だけでは示していない。
```

The definitions and limitation belong to this fictional sample. Do not transfer them into a rewrite whose source supplies only the three figures.

## Before/after using only the supplied figures

**Before**

> 6月の総訪問数は128,400件で、前月から3%減少した。検索流入は71,200件で前月比8%減、SNS経由の購入率は4.6%だった。

**After**

> 6月は総訪問数と検索流入がともに減少した。総訪問数は128,400件（前月比3%減）、検索流入は71,200件（同8%減）だった。SNS経由の購入率は4.6%だった。

**Preservation invariants:** all supplied values, units, comparison periods, and the descriptive character of the report. No new recommendation or causal explanation.

**Do not add:** a two-month trend, a site-average rate of 2.0%, an excluded-product rate of 2.1%, concentration in one product, an influencer explanation, or a priority to invest in SNS. Such details may be useful if verified elsewhere, but they are not present in this before text.

## Quality review

Can the reader identify the main result, its basis, and important limitations? Are conclusions no stronger than the evidence? Are relevant methods findable? Does the summary retain caveats that affect interpretation? Does any recommendation match the report's purpose and available evidence?

Use `../eval-rubric.md` qualitatively. No numerical naturalness score or zero-finding requirement establishes report quality.

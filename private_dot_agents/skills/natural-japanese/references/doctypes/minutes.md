# Minutes: make outcomes retrievable without inventing them

## Purpose and source boundary

Minutes record what was discussed, proposed, decided, assigned, or left open. They need not reproduce every utterance, but they must preserve relevant attribution, disagreement, uncertainty, and reasons. A verbatim record has a different purpose and should not be silently converted into outcome-only minutes.

**Source guidance:** The [2022 public-writing recommendation](../sources.md) treats minutes as records whose information must remain accurate and allows audience-appropriate presentation. The structure below is an editorial heuristic, not a requirement that every meeting have decisions or assigned actions.

## Information to retain when supplied

- Meeting name, date/time, and participants.
- Agenda items and the discussion needed to understand the outcomes.
- Confirmed decisions, including their limits and any recorded disagreement.
- Actions, with owner and deadline **when actually stated**.
- Deferred or unresolved issues and agreed next discussion, if any.
- Recording or transcription limitations when supplied and relevant.

A missing owner or deadline is a missing fact, not permission to assign one. An action can still be recorded without both fields; explain the missing information only when useful. Do not write 「未定（次回までに決める）」 unless the promise to decide next time is in the source. “Not recorded” and “not decided” are different.

## Arrangement

Make confirmed decisions and actions easy to find near the beginning or end. Organize discussion by agenda or another useful grouping. Stable labels such as 「決定事項」「宿題」「継続議題」 often help retrieval. Do not force every agenda heading to assert a decision.

Use prose when it helps explain an exchange or reason; keep lists for retrievable independent observations, advice, decisions, or actions. Chronology can remain when it matters. The same meeting can mix short record fragments and fuller explanations.

Use a record-appropriate register. Preserve direct quotes as quotes; do not polish a quotation into wording the speaker did not use. A paraphrase may remove fillers and repetition, but keep the original speech act. 「持ち帰って検討したい」 must not become 「了承した」.

If speaker identification is uncertain, label that uncertainty only when supported. Do not invent a recording method, note-taker, correction route, or speaker confidence level. If the source does not establish who spoke, avoid a confident attribution.

## Outcome distinctions

| Source status | Faithful record | Do not upgrade to |
|---|---|---|
| A proposal was made | 「佐藤が案を提案した」 | 「案を採用した」 |
| One participant supported it | 「鈴木が賛成した」 | 「全員が合意した」 |
| Discussion was deferred | 「次回改めて相談する」 | 「変更する方針で合意した」 |
| A request was made | 「確認を依頼した」 | 「確認を引き受けた」 |
| No deadline is stated | Leave it absent, or say it is not recorded if needed | Inventing a date |
| No response is recorded | Record the advice or request as such | Adding 「了承した」 |

An explicit decision to postpone can itself be a procedural decision. Do not dismiss it as “not a decision”; distinguish the postponement from a substantive outcome.

## Quality review

Can a reader locate the actual decisions, actions, and unresolved issues without rereading the entire record? Do headings, summaries, and tables carry the same certainty as the discussion? Are proposals, support, consensus, and assignment distinct? Have minority views or relevant conditions been lost in compression?

For advice or review meetings, retain the recipient's response when it is supplied. Never infer assent from silence. Do not pad empty sections to satisfy a template. See `../revision-guide.md` for selective editing and `../eval-rubric.md` for qualitative checks.

## Illustrative fictional sample

The following is a self-contained fictional record, not information available for other examples. All its participants, dates, and statements are invented for illustration and must not be transplanted into a user's minutes.

```text
# 在庫サービス開発定例（2026年7月10日）
出席：田中、佐藤、鈴木

## アラートのしきい値は継続検討
佐藤が在庫回転率を使う案を提案し、鈴木が賛成した。
採用するかどうかは、次回改めて相談する。

## 決定事項
- 在庫回転率案の採否は、次回改めて相談する。

## 継続議題
- 在庫アラートのしきい値の算出方法。
```

The procedural decision is visible, but the adoption decision remains open. No owner or deadline was added because this fictional meeting record does not supply one.

## Before/after: preserve the deferred outcome

**Before**

> 田中さんから在庫アラートについて説明があり、現行のしきい値だと誤検知が多いという話になった。佐藤さんはそれに対して在庫回転率を使う案を出し、鈴木さんも賛成した。最終的にどう決まったかは次回また相談することになった。

**After**

> 在庫アラートのしきい値は、次回改めて相談する。田中さんの説明を受け、現行のしきい値では誤検知が多いことが話題になった。佐藤さんが在庫回転率を使う案を出し、鈴木さんが賛成した。

**Preservation invariants:** the outcome is deferred; Tanaka explained, Sato proposed, and Suzuki supported; the current threshold was discussed as producing many false positives. The exact threshold, affected product class, action owner, and deadline are not supplied.

**Unfaithful counterexample**

> 在庫数から在庫回転率に変更する方針で合意した。田中が7月18日までに具体案を作成する。

This invents agreement, the current calculation basis, an assignment, and a deadline. Similarly, adding 「在庫数10個未満」「季節商品」 or changing the false-positive observation into Sato's attributed statement would add facts not established by the before text. Fluency and completeness do not excuse those changes.

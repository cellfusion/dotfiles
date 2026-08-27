## 開発ワークフロー

開発の手順はスキルが持つ。**応答・調査・確認質問より先に、該当するスキルを起動する。** 1% でも該当しそうなら起動する。

| 依頼 | 最初に起動するスキル |
|---|---|
| 新機能・変更・「作りたい」「追加したい」 | `brainstorming` → `writing-plans` → `subagent-driven-development` |
| バグ・不具合・「動かない」「直らない」 | `systematic-debugging` |
| 実装プランが既にある | `subagent-driven-development`（subagent が使えないときだけ `executing-plans`） |
| 実装が終わった・マージしたい | `finishing-a-development-branch` |
| 完了・テスト通過を主張する直前 | `verification-before-completion` |
| コードレビューの指摘を受け取った | `receiving-code-review` |

「単純な質問だから」「先に状況を調べてから」「今回は大げさだから」は起動しない理由にならない。

subagent として起動された場合、この指示は無視する。

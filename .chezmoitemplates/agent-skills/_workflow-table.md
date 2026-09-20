## 開発ワークフロー

開発の手順はスキルが持つ。ただし、スキルは依頼に必要な場合だけ起動する。ユーザーの依頼を読むこと、関連ファイルを調べること、確認質問をすることを、スキル起動の前提にしない。

| 依頼 | 最初に起動するスキル |
|---|---|
| 明確で局所的な変更 | 直接調査・実装する。設計の選択が残る場合だけ `brainstorming` |
| 意図や挙動が未確定な変更 | `brainstorming` |
| 複数層にまたがる設計変更 | `brainstorming`。必要なら `writing-plans` |
| バグ・不具合・「動かない」「直らない」 | 根本原因が未確定なら `systematic-debugging` |
| 実装プランが既にある | 小さければ `executing-plans`。並列性や独立した review が必要なら `multi-agent-development` |
| 実装が終わった・マージしたい | `finishing-a-development-branch` |
| 完了・テスト通過を主張する直前 | `verification-before-completion` |
| コードレビューの指摘を受け取った | `receiving-code-review` |

brainstorming はすべての変更に必要ではない。どのスキルを使うか、どの経路で進むかは親エージェントが依頼の明確さ、リスク、作業量から判断する。

subagent として起動された場合、この指示は無視する。

> **この環境での対応**
>
> | 論理名 | この環境での実体 |
> |---|---|
> | `[ask-user]` | 選択肢を提示してユーザーの応答を待つ。勝手に決めて進まない |
> | `[dispatch-subagent: X]` | サブエージェント `X` を spawn する |
> | `[resume-subagent]` | 継続する機構は無い。新しいサブエージェントを立て、報告ファイルで記憶を引き継ぐ |
> | `[deterministic-loop]` | 利用不可。あなた自身がループを回し、ラウンド数を数える |
> | `[todo]` | 作業リストを管理するツール。無ければ ledger ファイルで代替する |
> | `[web-search]` | `web_search` ツール |
> | `[retry-outside-sandbox]` | 同じコマンドを `sandbox_permissions=require_escalated` で再実行し、`justification` にそのコマンドを sandbox の外で実行する理由を書く |

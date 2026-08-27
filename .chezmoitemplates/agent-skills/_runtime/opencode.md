> **この環境での対応**
>
> | 論理名 | この環境での実体 |
> |---|---|
> | `[ask-user]` | `question` ツール。使えなければ選択肢を提示して応答を待つ |
> | `[dispatch-subagent: X]` | `task` ツールでサブエージェント `X` を指定する。または `@X` で呼ぶ |
> | `[resume-subagent]` | 継続する機構は無い。新しいサブエージェントを立て、報告ファイルで記憶を引き継ぐ |
> | `[deterministic-loop]` | 利用不可。あなた自身がループを回し、ラウンド数を数える |
> | `[todo]` | `todowrite` ツール |
> | `[web-search]` | `websearch` ツール |
> | `[retry-outside-sandbox]` | 利用可能な permission / escalation 機構で同じコマンドを sandbox 外へ再実行する。機構が無ければ失敗として扱う |

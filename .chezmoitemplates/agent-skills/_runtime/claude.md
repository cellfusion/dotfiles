> **この環境での対応**
>
> | 論理名 | この環境での実体 |
> |---|---|
> | `[ask-user]` | `AskUserQuestion` ツール |
> | `[dispatch-subagent: X]` | `Agent` ツール（`subagent_type: X`） |
> | `[resume-subagent]` | `SendMessage` ツール |
> | `[deterministic-loop]` | `Workflow` ツール（利用可） |
> | `[todo]` | 作業リストを管理するツール。無ければ ledger ファイルで代替する |
> | `[web-search]` | `WebSearch` ツール |
> | `[retry-outside-sandbox]` | permission prompt を伴う実行で同じコマンドを sandbox 外へ再試行する。利用できない場合は失敗として扱う |

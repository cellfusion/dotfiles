// PR がエージェントの指示ファイルを変更しているかを判定する。
// 変更していると、PR head をチェックアウトした worktree でレビューする agent は
// PR の作者が書いた指示を読み込むことになる。pr-review スキルはその状態を禁じている。

// パスの最終要素がこれらのいずれかなら指示ファイルとする。
// gh pr diff --name-only はリポジトリのルートからの相対パスを返すので、
// packages/api/CLAUDE.md のように入れ子になったものも拾う必要がある。
export const INSTRUCTION_FILE_NAMES = ["CLAUDE.md", "CLAUDE.local.md", "AGENTS.md"];

// パスの要素にこれらのいずれかが含まれるなら、その配下は指示ファイルとする。
export const INSTRUCTION_DIR_NAMES = [".claude", ".agents"];

export function touchesInstructions(changedPaths: string[]): boolean {
  return changedPaths.some((path) => {
    const segments = path.split("/");
    const fileName = segments[segments.length - 1];
    if (INSTRUCTION_FILE_NAMES.includes(fileName)) {
      return true;
    }
    return segments.some((segment) => INSTRUCTION_DIR_NAMES.includes(segment));
  });
}

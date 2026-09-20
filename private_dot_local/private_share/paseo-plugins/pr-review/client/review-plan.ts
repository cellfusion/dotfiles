import type { PreparedPlan } from "../shared/contracts";

/**
 * 確認 Modal に 1 行ずつ出す説明文を組み立てる。画面を描画せずにテストできるよう、
 * 純粋関数にしてある。
 */
export function describeReviewPlan(plan: PreparedPlan, provider: string): string[] {
  const lines: string[] = [];

  if (plan.action === "checkout") {
    lines.push("PR head をチェックアウトした worktree を作る");
  } else {
    lines.push(`${plan.baseRefName} から分岐した worktree を作る`);
    lines.push(`新しいブランチ: ${plan.branchName ?? "(未指定)"}`);
    lines.push(`base ブランチ: ${plan.baseRefName}`);
  }

  if (plan.instructionsChanged) {
    lines.push(
      "この PR は CLAUDE.md / AGENTS.md / .claude/ / .agents/ のいずれかを変更している。" +
        "レビューする agent が PR 側の指示を読み込まないよう、base から分岐する",
    );
  }

  lines.push(`provider: ${provider}`);
  return lines;
}

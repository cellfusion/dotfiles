import type { PluginContext } from "@getpaseo/plugin";
import { runCommand } from "./commands";
import { listPullRequests, preparePullRequest } from "./contracts";
import { PullRequestSurface } from "./main.client";

// PR がこれらを変更していると、レビューする agent の指示が PR 側に置き換わる。
// 末尾が "/" の項目は前方一致で判定する。
const INSTRUCTION_PATHS = ["CLAUDE.md", "AGENTS.md", ".claude/", ".agents/"];

interface GhPullRequest {
  number: number;
  title: string;
  author: { login?: string } | null;
  headRefName: string;
  updatedAt: string;
}

function touchesInstructions(changedPaths: string[]): boolean {
  return changedPaths.some((path) =>
    INSTRUCTION_PATHS.some((entry) =>
      entry.endsWith("/") ? path.startsWith(entry) : path === entry,
    ),
  );
}

export default function contribute(plugin: PluginContext) {
  plugin.handle(listPullRequests, async ({ projectRootPath }) => {
    const stdout = await runCommand(
      "gh",
      [
        "pr",
        "list",
        "--state",
        "open",
        "--limit",
        "50",
        "--json",
        "number,title,author,headRefName,updatedAt",
      ],
      projectRootPath,
    );
    const raw = JSON.parse(stdout) as GhPullRequest[];
    return {
      pulls: raw.map((entry) => ({
        number: entry.number,
        title: entry.title,
        author: entry.author?.login ?? "unknown",
        headRefName: entry.headRefName,
        updatedAt: entry.updatedAt,
      })),
    };
  });

  plugin.handle(preparePullRequest, async ({ projectRootPath, number }) => {
    const viewOut = await runCommand(
      "gh",
      ["pr", "view", String(number), "--json", "baseRefName"],
      projectRootPath,
    );
    const { baseRefName } = JSON.parse(viewOut) as { baseRefName: string };

    // gh pr diff はサーバー側の差分を返すので、PR head の object がローカルに
    // 無くても動く。git diff は fetch していないと失敗する。
    const diffOut = await runCommand(
      "gh",
      ["pr", "diff", String(number), "--name-only"],
      projectRootPath,
    );
    const changedPaths = diffOut
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line.length > 0);
    const instructionsChanged = touchesInstructions(changedPaths);

    return {
      action: instructionsChanged ? ("branch-off" as const) : ("checkout" as const),
      baseRefName,
      branchName: instructionsChanged ? `pr-review/${number}-base` : null,
      instructionsChanged,
    };
  });

  plugin.addSurface("pull-requests", PullRequestSurface);
  plugin.addSidebarItem({
    id: "pull-requests",
    title: "PR レビュー",
    icon: "GitPullRequest",
    surface: "pull-requests",
  });
  plugin.addCommandCenterItem({
    id: "open-pull-requests",
    title: "PR をレビューする",
    icon: "GitPullRequest",
    keywords: ["pr", "review", "pull request", "レビュー"],
    context: "global",
    onSelect({ openSurface }) {
      openSurface("pull-requests");
    },
  });

  return () => {};
}

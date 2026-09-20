import type { PluginServerContext } from "@getpaseo/plugin/server";
import { runCommand } from "./server/commands";
import { touchesInstructions } from "./server/instructions";
import { listPullRequests, preparePullRequest } from "./shared/contracts";

interface GhPullRequest {
  number: number;
  title: string;
  author: { login?: string } | null;
  headRefName: string;
  updatedAt: string;
}

export default function contribute(server: PluginServerContext) {
  server.handle(listPullRequests, async ({ projectRootPath }) => {
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

  server.handle(preparePullRequest, async ({ projectRootPath, number }) => {
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

  return () => {};
}

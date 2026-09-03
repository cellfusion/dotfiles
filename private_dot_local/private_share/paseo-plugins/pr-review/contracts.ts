import { defineRpc } from "@getpaseo/plugin";
import { z } from "zod";

export const PullRequestSchema = z.object({
  number: z.number().int().positive(),
  title: z.string(),
  author: z.string(),
  headRefName: z.string(),
  updatedAt: z.string(),
});

export type PullRequest = z.infer<typeof PullRequestSchema>;

/** 対象リポジトリの open な PR を列挙する。 */
export const listPullRequests = defineRpc({
  name: "pr-review.pulls.list",
  input: z.object({ projectRootPath: z.string().min(1) }),
  output: z.object({ pulls: z.array(PullRequestSchema) }),
});

/** preparePullRequest が返す、作る workspace の形。 */
export const PreparedPlanSchema = z.object({
  action: z.enum(["checkout", "branch-off"]),
  baseRefName: z.string().min(1),
  branchName: z.string().nullable(),
  instructionsChanged: z.boolean(),
});

export type PreparedPlan = z.infer<typeof PreparedPlanSchema>;

/**
 * 1 件の PR について、作る workspace の形を決める。PR が指示ファイルを変更していれば
 * base から分岐した worktree にし、そうでなければ PR head をチェックアウトする。
 */
export const preparePullRequest = defineRpc({
  name: "pr-review.pulls.prepare",
  input: z.object({
    projectRootPath: z.string().min(1),
    number: z.number().int().positive(),
  }),
  output: PreparedPlanSchema,
});

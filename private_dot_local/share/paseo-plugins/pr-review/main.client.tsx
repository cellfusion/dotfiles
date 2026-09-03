import { type PluginSurfaceProps, usePaseo, useRpc } from "@getpaseo/plugin";
import { useQuery } from "@tanstack/react-query";
import React, { useMemo, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, Text } from "react-native";
import { listPullRequests, preparePullRequest } from "./contracts";

// daemon config に pr-review という名前の profile があればそれを使う。
// 無ければこの値を使う。
const PROFILE_NAME = "pr-review";
const DEFAULT_PROVIDER = "claude/claude-opus-5";

export function PullRequestSurface({ theme, layout }: PluginSurfaceProps) {
  const paseo = usePaseo();
  const fetchPullRequests = useRpc(listPullRequests);
  const prepare = useRpc(preparePullRequest);
  const [projectRootPath, setProjectRootPath] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const projects = useQuery({
    queryKey: ["pr-review", "projects"],
    queryFn: async () => {
      const result = await paseo.projects.list();
      return result.projects.filter((project) => project.projectKind === "git");
    },
  });

  const pulls = useQuery({
    queryKey: ["pr-review", "pulls", projectRootPath],
    enabled: projectRootPath !== null,
    queryFn: async () => {
      const result = await fetchPullRequests({ projectRootPath: projectRootPath as string });
      return result.pulls;
    },
  });

  const styles = useMemo(
    () => ({
      screen: {
        flex: 1,
        padding: layout.compact ? 16 : 24,
        gap: layout.compact ? 8 : 12,
        backgroundColor: theme.colors.surface0,
      },
      heading: { color: theme.colors.foreground, fontSize: layout.compact ? 18 : 22 },
      label: { color: theme.colors.foregroundMuted, fontSize: 13 },
      row: {
        padding: 12,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: theme.colors.border,
        backgroundColor: theme.colors.surface1,
        gap: 4,
      },
      rowSelected: {
        padding: 12,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: theme.colors.accent,
        backgroundColor: theme.colors.surface2,
        gap: 4,
      },
      title: { color: theme.colors.foreground, fontSize: 15 },
      meta: { color: theme.colors.foregroundMuted, fontSize: 12 },
      status: { color: theme.colors.foregroundMuted, fontSize: 13 },
      error: { color: theme.colors.statusDanger, fontSize: 13 },
    }),
    [theme, layout.compact],
  );

  async function resolveAgentConfig(): Promise<{ provider: string; modeId?: string; thinkingOptionId?: string }> {
    const { config } = await paseo.config.get();
    const profile = config.agentProfiles?.find((entry) => entry.name === PROFILE_NAME);
    if (profile === undefined) {
      return { provider: DEFAULT_PROVIDER };
    }
    return {
      provider: profile.model === undefined ? profile.provider : `${profile.provider}/${profile.model}`,
      modeId: profile.modeId,
      thinkingOptionId: profile.thinkingOptionId,
    };
  }

  async function startReview(number: number, title: string) {
    if (projectRootPath === null) {
      return;
    }
    setStatus(`PR #${number} の workspace を作っている`);
    try {
      const plan = await prepare({ projectRootPath, number });
      const source =
        plan.action === "checkout"
          ? {
              kind: "worktree" as const,
              cwd: projectRootPath,
              action: "checkout" as const,
              checkoutSource: { kind: "change_request" as const, forge: "github", number },
            }
          : {
              kind: "worktree" as const,
              cwd: projectRootPath,
              action: "branch-off" as const,
              branchName: plan.branchName ?? `pr-review/${number}-base`,
              baseBranch: plan.baseRefName,
            };
      const workspace = await paseo.workspaces.create({
        title: `pr-review #${number} ${title}`,
        source,
      });
      const notice = plan.instructionsChanged
        ? [
            "",
            "",
            "この PR は CLAUDE.md / AGENTS.md / .claude/ / .agents/ のいずれかを変更している。",
            `この workspace は ${plan.baseRefName} から分岐したもので、PR head のチェックアウトではない。`,
            "レビュー対象の checkout は pr-review スキルの手順で別に作る。",
          ].join("\n")
        : "";
      const config = await resolveAgentConfig();
      await workspace.agents.create({
        config,
        title: `pr-review/${number}`,
        prompt: `/pr-review ${number}${notice}`,
      });
      setStatus(`PR #${number} のレビューを開始した`);
    } catch (error) {
      // 呼び出し側は startReview の Promise を待たないので、ここで握って画面に出す。
      // 再送出すると unhandled rejection になり、失敗が画面に出ない。
      const detail = error instanceof Error ? error.message : String(error);
      setStatus(`PR #${number} のレビューを開始できなかった: ${detail}`);
    }
  }

  return (
    <ScrollView contentContainerStyle={styles.screen}>
      <Text style={styles.heading}>PR レビュー</Text>

      <Text style={styles.label}>プロジェクト</Text>
      {projects.isPending ? <ActivityIndicator color={theme.colors.accent} /> : null}
      {projects.isError ? (
        <Text style={styles.error}>プロジェクトの一覧を取得できなかった</Text>
      ) : null}
      {(projects.data ?? []).map((project) => (
        <Pressable
          key={project.projectId}
          accessibilityRole="button"
          accessibilityLabel={`プロジェクト ${project.projectDisplayName} を選ぶ`}
          style={project.projectRootPath === projectRootPath ? styles.rowSelected : styles.row}
          onPress={() => {
            setProjectRootPath(project.projectRootPath);
            setStatus(null);
          }}
        >
          <Text style={styles.title}>{project.projectDisplayName}</Text>
          <Text style={styles.meta}>{project.projectRootPath}</Text>
        </Pressable>
      ))}

      {projectRootPath === null ? null : (
        <>
          <Text style={styles.label}>Pull Request</Text>
          {pulls.isPending ? <ActivityIndicator color={theme.colors.accent} /> : null}
          {pulls.isError ? (
            <Text style={styles.error}>PR の一覧を取得できなかった</Text>
          ) : null}
          {(pulls.data ?? []).map((pull) => (
            <Pressable
              key={pull.number}
              accessibilityRole="button"
              accessibilityLabel={`PR ${pull.number} をレビューする`}
              style={styles.row}
              onPress={() => {
                void startReview(pull.number, pull.title);
              }}
            >
              <Text style={styles.title}>{`#${pull.number} ${pull.title}`}</Text>
              <Text style={styles.meta}>{`${pull.author} · ${pull.headRefName}`}</Text>
            </Pressable>
          ))}
        </>
      )}

      {status === null ? null : <Text style={styles.status}>{status}</Text>}
    </ScrollView>
  );
}

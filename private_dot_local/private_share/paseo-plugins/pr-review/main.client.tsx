import { type PluginSurfaceProps, usePaseo, useRpc } from "@getpaseo/plugin";
import { Modal, useToast } from "@getpaseo/plugin/react-native";
import { useQuery } from "@tanstack/react-query";
import React, { useMemo, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, Text, View } from "react-native";
import {
  type PreparedPlan,
  type PullRequest,
  listPullRequests,
  preparePullRequest,
} from "./contracts";
import { resolveProviderFamily } from "./provider-resolution";
import { describeReviewPlan } from "./review-plan";

const REVIEW_MODEL = "claude-opus-5";

interface PendingReview {
  pull: PullRequest;
  plan: PreparedPlan;
  provider: string;
}

export function PullRequestSurface({ theme, layout }: PluginSurfaceProps) {
  const paseo = usePaseo();
  const toast = useToast();
  const fetchPullRequests = useRpc(listPullRequests);
  const prepare = useRpc(preparePullRequest);
  // 開いているアコーディオンの行を表す。null ならどの行も開いていない。
  const [projectRootPath, setProjectRootPath] = useState<string | null>(null);
  // 確認 Modal に出す内容。null なら Modal は閉じている。
  const [pending, setPending] = useState<PendingReview | null>(null);
  // 準備中と起動中はどの PR 行も押せないようにする。連打すると
  // workspaces.create が複数回呼ばれ、同じ PR に worktree と agent が複数できる。
  const [startingNumber, setStartingNumber] = useState<number | null>(null);

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
      card: {
        borderRadius: 8,
        borderWidth: 1,
        borderColor: theme.colors.border,
        backgroundColor: theme.colors.surface1,
      },
      cardOpen: {
        borderRadius: 8,
        borderWidth: 1,
        borderColor: theme.colors.accent,
        backgroundColor: theme.colors.surface2,
      },
      header: { padding: 12, gap: 4 },
      pulls: { paddingHorizontal: 12, paddingBottom: 12, gap: 8 },
      pullRow: {
        padding: 12,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: theme.colors.border,
        backgroundColor: theme.colors.surface1,
        gap: 4,
      },
      title: { color: theme.colors.foreground, fontSize: 15 },
      meta: { color: theme.colors.foregroundMuted, fontSize: 12 },
      error: { color: theme.colors.statusDanger, fontSize: 13 },
      modalBody: { padding: layout.compact ? 12 : 16, gap: 8 },
      modalTitle: { color: theme.colors.foreground, fontSize: 15 },
      modalLine: { color: theme.colors.foregroundMuted, fontSize: 13 },
      buttonRow: { flexDirection: "row" as const, gap: 8, marginTop: 8 },
      primaryButton: {
        flex: 1,
        padding: 12,
        borderRadius: 8,
        backgroundColor: theme.colors.accent,
      },
      primaryLabel: { color: theme.colors.accentForeground, textAlign: "center" as const },
      secondaryButton: {
        flex: 1,
        padding: 12,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: theme.colors.border,
      },
      secondaryLabel: { color: theme.colors.foreground, textAlign: "center" as const },
    }),
    [theme, layout.compact],
  );

  // 使う provider を決める。daemon config の構造ではなく、型の付いた
  // provider の一覧から取る。
  async function resolveProvider(): Promise<string> {
    const { providers } = await paseo.providers.listAvailable();
    const configuredProviders = providers
      .filter((entry) => entry.available)
      .map((entry) => entry.provider);
    const family = resolveProviderFamily("claude", process.env.AGENT_ENV, configuredProviders);
    return `${family}/${REVIEW_MODEL}`;
  }

  // PR を押した時点では workspace を作らない。作る内容を集めて Modal を開く。
  async function prepareReview(pull: PullRequest) {
    if (projectRootPath === null) {
      return;
    }
    setStartingNumber(pull.number);
    try {
      const plan = await prepare({ projectRootPath, number: pull.number });
      const provider = await resolveProvider();
      setPending({ pull, plan, provider });
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      toast.error(`PR #${pull.number} の準備に失敗した: ${detail}`);
    } finally {
      setStartingNumber(null);
    }
  }

  async function confirmReview() {
    if (pending === null || projectRootPath === null) {
      return;
    }
    const { pull, plan, provider } = pending;
    const number = pull.number;
    setStartingNumber(number);
    try {
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
      // 指示ファイルを変更した PR は base から分岐する。PR head のチェックアウトで
      // ないことを workspace 一覧で見分けられるよう、title の先頭に印を付ける。
      const titlePrefix = plan.instructionsChanged ? "[base] " : "";
      const workspace = await paseo.workspaces.create({
        title: `${titlePrefix}pr-review #${number} ${pull.title}`,
        source,
      });
      // pr-review スキルは引数を正の整数 1 個だけと定めている。説明を足すと
      // 引数が数値に一致しなくなり、レビューが始まらない。
      await workspace.agents.create({
        config: { provider },
        title: `pr-review/${number}`,
        prompt: `/pr-review ${number}`,
      });
      setPending(null);
      toast.show(`PR #${number} のレビューを開始した`, { variant: "success" });
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      toast.error(`PR #${number} のレビューを開始できなかった: ${detail}`);
    } finally {
      setStartingNumber(null);
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

      {(projects.data ?? []).map((project) => {
        const open = project.projectRootPath === projectRootPath;
        return (
          <View key={project.projectId} style={open ? styles.cardOpen : styles.card}>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={`プロジェクト ${project.projectDisplayName} を${open ? "閉じる" : "開く"}`}
              style={styles.header}
              onPress={() => {
                setProjectRootPath(open ? null : project.projectRootPath);
              }}
            >
              <Text style={styles.title}>{project.projectDisplayName}</Text>
              <Text style={styles.meta}>{project.projectRootPath}</Text>
            </Pressable>

            {open ? (
              <View style={styles.pulls}>
                {pulls.isPending ? <ActivityIndicator color={theme.colors.accent} /> : null}
                {pulls.isError ? (
                  <Text style={styles.error}>PR の一覧を取得できなかった</Text>
                ) : null}
                {pulls.isSuccess && pulls.data.length === 0 ? (
                  <Text style={styles.meta}>open な PR は無い</Text>
                ) : null}
                {(pulls.data ?? []).map((pull) => (
                  <Pressable
                    key={pull.number}
                    accessibilityRole="button"
                    accessibilityLabel={`PR ${pull.number} をレビューする`}
                    style={styles.pullRow}
                    disabled={startingNumber !== null}
                    onPress={() => {
                      void prepareReview(pull);
                    }}
                  >
                    <Text style={styles.title}>{`#${pull.number} ${pull.title}`}</Text>
                    <Text style={styles.meta}>{`${pull.author} · ${pull.headRefName}`}</Text>
                  </Pressable>
                ))}
              </View>
            ) : null}
          </View>
        );
      })}

      <Modal
        title={pending === null ? "PR をレビューする" : `PR #${pending.pull.number} をレビューする`}
        open={pending !== null}
        onOpenChange={(next) => {
          if (!next) {
            setPending(null);
          }
        }}
      >
        <Modal.Content>
          {pending === null ? null : (
            <View style={styles.modalBody}>
              <Text style={styles.modalTitle}>{pending.pull.title}</Text>
              <Text
                style={styles.modalLine}
              >{`${pending.pull.author} · ${pending.pull.headRefName}`}</Text>
              {describeReviewPlan(pending.plan, pending.provider).map((line) => (
                <Text key={line} style={styles.modalLine}>
                  {line}
                </Text>
              ))}
              <View style={styles.buttonRow}>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel="やめる"
                  style={styles.secondaryButton}
                  disabled={startingNumber !== null}
                  onPress={() => {
                    setPending(null);
                  }}
                >
                  <Text style={styles.secondaryLabel}>やめる</Text>
                </Pressable>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel="レビューを開始"
                  style={styles.primaryButton}
                  disabled={startingNumber !== null}
                  onPress={() => {
                    void confirmReview();
                  }}
                >
                  <Text style={styles.primaryLabel}>レビューを開始</Text>
                </Pressable>
              </View>
            </View>
          )}
        </Modal.Content>
      </Modal>
    </ScrollView>
  );
}

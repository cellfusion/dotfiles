import type { PluginClientContext } from "@getpaseo/plugin/client";
import { PullRequestSurface } from "./client/main";

export default function contribute(client: PluginClientContext) {
  client.addSurface("pull-requests", PullRequestSurface);
  client.addSidebarItem({
    id: "pull-requests",
    title: "PR レビュー",
    icon: "GitPullRequest",
    surface: "pull-requests",
  });
  client.addCommandCenterItem({
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

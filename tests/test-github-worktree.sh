#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

status=0
python3 -B - "$CHEZMOI_SOURCE" <<'PY' || status=$?
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

source = Path(sys.argv[1]) / 'private_dot_local/bin/executable_github-worktree'
loader = importlib.machinery.SourceFileLoader('github_worktree', str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class RepositoryRouting(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.original = Path.cwd()
        self.addCleanup(os.chdir, self.original)
        self.target = self.repository('target', 'git@github.com:owner/project.git')
        self.other = self.repository('other', 'https://github.com/other/project.git')
        self.child = self.base / 'child'
        self.git(self.target, 'worktree', 'add', '-b', 'review', str(self.child))
        self.workspaces = [
            {'workspace_id': 'other', 'worktree': {'checkout_path': str(self.other)}},
            {'workspace_id': 'child', 'worktree': {'checkout_path': str(self.child)}},
            {'workspace_id': 'parent', 'worktree': {'checkout_path': str(self.target)}},
        ]
        self.panes = []
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, {'HERDR_BIN_PATH': 'herdr'}).start()
        patch.object(module, 'run', side_effect=self.herdr).start()
        os.chdir(self.base)

    def git(self, directory, *args):
        return subprocess.check_output(['git', '-C', str(directory), *args],
                                       text=True, stderr=subprocess.PIPE)

    def repository(self, name, remote):
        directory = self.base / name
        directory.mkdir()
        self.git(directory, 'init', '-b', 'main')
        self.git(directory, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                 'commit', '--allow-empty', '-m', 'initial')
        self.git(directory, 'remote', 'add', 'origin', remote)
        return directory

    def herdr(self, *args, **kwargs):
        if args == ('herdr', 'workspace', 'list'):
            return json.dumps({'result': {'workspaces': self.workspaces}})
        if args == ('herdr', 'pane', 'list'):
            return json.dumps({'result': {'panes': self.panes}})
        raise AssertionError(args)

    def test_selects_main_checkout_of_matching_owner_from_non_git_cwd(self):
        self.assertEqual(module.target_checkout({
            'url': 'https://github.com/OWNER/project', 'nameWithOwner': 'owner/project'
        }), self.target)

    def test_does_not_route_to_same_name_under_different_owner_or_host(self):
        for url in ('https://github.com/missing/project', 'https://enterprise.test/owner/project'):
            with self.subTest(url=url), self.assertRaises(RuntimeError):
                module.target_checkout({'url': url, 'nameWithOwner': 'missing/project'})

    def test_discovers_workspace_before_repository_metadata_arrives(self):
        self.workspaces = [{'workspace_id': 'parent'}]
        subdir = self.target / 'nested'
        subdir.mkdir()
        self.panes = [{'workspace_id': 'parent', 'cwd': str(subdir)}]
        self.assertEqual(module.target_checkout({
            'url': 'https://github.com/owner/project', 'nameWithOwner': 'owner/project'
        }), self.target)

    def test_pane_in_another_repo_does_not_change_workspace_repository(self):
        self.workspaces = self.workspaces[:1]
        self.panes = [{'workspace_id': 'other', 'cwd': str(self.target)}]
        with self.assertRaises(RuntimeError):
            module.target_checkout({
                'url': 'https://github.com/owner/project', 'nameWithOwner': 'owner/project'
            })

    def test_missing_branch_never_creates_checkout_or_workspace(self):
        os.chdir(self.target)
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'branch', 'missing']), \
                self.assertRaisesRegex(RuntimeError, 'local branch'):
            module.main()
        self.assertEqual(self.git(self.target, 'branch', '--format=%(refname:short)').splitlines(),
                         ['main', 'review'])

    def test_missing_remote_branch_does_not_create_local_branch(self):
        os.chdir(self.target)
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'branch', 'missing', '--remote', 'origin']), \
                self.assertRaisesRegex(RuntimeError, 'remote branch'):
            module.main()
        self.assertEqual(self.git(self.target, 'branch', '--format=%(refname:short)').splitlines(),
                         ['main', 'review'])

    def test_remote_selection_rejects_unrelated_existing_local_branch(self):
        os.chdir(self.target)
        self.git(self.target, 'remote', 'add', 'upstream', 'https://github.com/upstream/project.git')
        self.git(self.target, 'update-ref', 'refs/remotes/upstream/review', 'main')
        for tracking in (False, True):
            if tracking:
                self.git(self.target, 'config', 'branch.review.remote', 'origin')
                self.git(self.target, 'config', 'branch.review.merge', 'refs/heads/review')
            with self.subTest(tracking=tracking), patch.dict(os.environ, HERDR_ENV='1'), \
                    patch.object(sys, 'argv', ['github-worktree', 'branch', 'review', '--remote', 'upstream']), \
                    self.assertRaisesRegex(RuntimeError, 'does not track'):
                module.main()
        self.assertEqual(self.git(self.target, 'rev-parse', 'review'),
                         self.git(self.target, 'rev-parse', 'main'))

    def test_branch_switch_runs_hooks_after_approval_preflight(self):
        os.chdir(self.target)
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'branch', 'review']), \
                patch.object(module, 'run', return_value='{"state":"approved","commands":[],"stale":[]}') as run:
            module.main()
        self.assertEqual(run.call_args_list[0].args, ('wt', 'config', 'approvals', 'list', '--format=json'))
        switch = run.call_args_list[1].args
        self.assertEqual(switch[:3], ('wt', 'switch', '--no-cd'))
        self.assertNotIn('--no-hooks', switch)
        self.assertNotIn('--yes', switch)

    def test_unapproved_project_commands_block_switch(self):
        os.chdir(self.target)
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'branch', 'review']), \
                patch.object(module, 'run', return_value='{"state":"approval_required"}') as run, \
                self.assertRaisesRegex(RuntimeError, 'approvals add'):
            module.main()
        self.assertEqual(run.call_count, 1)

    def test_interactive_approval_allows_switch(self):
        os.chdir(self.target)
        unapproved = '{"state":"approval_required","commands":[{"approved":false}],"stale":[]}'
        approved = '{"state":"approved","commands":[{"approved":true}],"stale":[]}'
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'branch', 'review']), \
                patch.object(sys.stdin, 'isatty', return_value=True), \
                patch.object(module, 'run', side_effect=[unapproved, None, approved, None]) as run:
            module.main()
        self.assertEqual(run.call_args_list[-1].args[:3], ('wt', 'switch', '--no-cd'))

    def test_declined_approval_does_not_switch(self):
        os.chdir(self.target)
        unapproved = '{"state":"approval_required","commands":[{"approved":false}],"stale":[]}'
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'branch', 'review']), \
                patch.object(sys.stdin, 'isatty', return_value=True), \
                patch.object(module, 'run', side_effect=[unapproved, None, unapproved]) as run, \
                self.assertRaisesRegex(RuntimeError, 'approval'):
            module.main()
        self.assertFalse(any(call.args[:2] == ('wt', 'switch') for call in run.call_args_list))

    def test_new_branch_creates_from_current_checkout(self):
        os.chdir(self.target)
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'new', 'feature/new']), \
                patch.object(module, 'run', return_value='{"state":"no_commands","commands":[],"stale":[]}') as run:
            module.main()
        switch = run.call_args_list[1].args
        self.assertIn('--create', switch)
        self.assertEqual(switch[switch.index('--base') + 1], '@')
        self.assertIn('feature/new', switch)

    def test_lazygit_branch_creation_works_without_herdr(self):
        os.chdir(self.target)
        with patch.dict(os.environ, HERDR_ENV='0'), \
                patch.object(sys, 'argv', ['github-worktree', 'new', 'feature/outside']), \
                patch.object(module, 'run', return_value='{"state":"no_commands","commands":[],"stale":[]}') as run:
            module.main()
        switch = run.call_args_list[1].args
        self.assertEqual(switch[:2], ('wt', 'switch'))
        self.assertIn('feature/outside', switch)
        self.assertNotIn('--execute', switch)

    def test_review_requests_approval_before_launch(self):
        os.chdir(self.target)
        responses = [
            '{"nameWithOwner":"owner/project","defaultBranchRef":{"name":"main"},"url":"https://github.com/owner/project"}',
            'https://github.com/owner/project/pull/12',
            '{"state":"approval_required","commands":[{"approved":false}],"stale":[]}',
            None,
            '{"state":"approved","commands":[{"approved":true}],"stale":[]}',
            None,
        ]
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'pr', '12', '--review']), \
                patch.object(sys.stdin, 'isatty', return_value=True), \
                patch.object(module, 'target_checkout', return_value=self.target), \
                patch.object(module, 'run', side_effect=responses) as run:
            module.main()
        self.assertEqual(run.call_args_list[-1].args[0], 'pr-review')

    def test_open_worktree_cannot_be_removed(self):
        os.chdir(self.target)
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'remove', str(self.child)]), \
                self.assertRaisesRegex(RuntimeError, 'open in Herdr'):
            module.main()

    def test_worktree_used_by_pane_in_other_workspace_cannot_be_removed(self):
        os.chdir(self.target)
        self.workspaces = self.workspaces[2:]
        self.panes = [{'workspace_id': 'parent', 'cwd': str(self.child)}]
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'remove', str(self.child)]), \
                self.assertRaisesRegex(RuntimeError, 'open in Herdr'):
            module.main()

    def test_closed_worktree_removal_preserves_branch_and_hooks(self):
        os.chdir(self.target)
        self.workspaces = self.workspaces[2:]
        def commands(*args, **kwargs):
            if args == ('wt', 'config', 'approvals', 'list', '--format=json'):
                return '{"state":"no_commands","commands":[],"stale":[]}'
            if args[:2] == ('wt', 'remove'):
                return None
            return self.herdr(*args, **kwargs)
        with patch.dict(os.environ, HERDR_ENV='1'), \
                patch.object(sys, 'argv', ['github-worktree', 'remove', str(self.child)]), \
                patch.object(module, 'run', side_effect=commands) as run:
            module.main()
        self.assertEqual(run.call_args.args,
                         ('wt', 'remove', '--foreground', '--no-delete-branch', str(self.child)))

    def test_invalid_approval_data_fails_closed(self):
        os.chdir(self.target)
        for response in ('{}', '{"state":"unknown"}', '{"state":"approved","commands":[{"approved":false}],"stale":[]}'):
            with self.subTest(response=response), patch.dict(os.environ, HERDR_ENV='1'), \
                    patch.object(sys, 'argv', ['github-worktree', 'branch', 'review']), \
                    patch.object(module, 'run', return_value=response) as run, \
                    self.assertRaises(RuntimeError):
                module.main()
            self.assertEqual(run.call_count, 1)



class DirectSelection(unittest.TestCase):
    def test_invalid_numbers_fail_before_external_commands(self):
        for value in ('0', '-1', 'abc', '1;touch /tmp/unwanted'):
            with self.subTest(value=value), patch.dict(os.environ, HERDR_ENV='1'), \
                    patch.object(sys, 'argv', ['github-worktree', 'pr', value]), \
                    patch.object(module, 'run') as run, self.assertRaises(SystemExit) as error:
                module.main()
            self.assertEqual(error.exception.code, 2)
            run.assert_not_called()

    def test_review_is_rejected_for_issue_and_branch(self):
        for kind in ('issue', 'branch'):
            with self.subTest(kind=kind), patch.dict(os.environ, HERDR_ENV='1'), \
                    patch.object(sys, 'argv', ['github-worktree', kind, '12', '--review']), \
                    patch.object(module, 'run') as run, self.assertRaises(SystemExit) as error:
                module.main()
            self.assertEqual(error.exception.code, 2)
            run.assert_not_called()


unittest.main(argv=['github-worktree'])
PY
assert_eq "$status" 0 'GitHub repository routing invariants'
assert_summary

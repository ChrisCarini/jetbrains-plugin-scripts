# jetbrains-plugin-scripts
Scripts to help automate JetBrains plugin development.

## Contents

| Path | Description |
| --- | --- |
| [`upgrade_all_intellij_plugins/`](upgrade_all_intellij_plugins/) | **Manual cross-repository dispatcher** that triggers the existing `update-plugin-platform-version.yml` workflow in every allowlisted JetBrains plugin repository. |
| [`update_plugins_for_new_jetbrains_release/`](update_plugins_for_new_jetbrains_release/) | Older local-checkout helper that edits plugin files for a new JetBrains release. |
| `0*.sh`, `iterate_over_all_ij_plugin_repos.sh` | Older local-checkout maintenance helpers. |

## Upgrade IntelliJ in all plugin repositories

See [`upgrade_all_intellij_plugins/README.md`](upgrade_all_intellij_plugins/README.md)
for the full documentation. In short:

- Run the **"Upgrade IntelliJ Platform version in all plugin repositories"**
  workflow from the Actions tab (it is `workflow_dispatch`-only).
- `dry_run` defaults to **true** - validate first, dispatch second.
- Targets come from an explicit allowlist,
  [`upgrade_all_intellij_plugins/plugin-repos.txt`](upgrade_all_intellij_plugins/plugin-repos.txt).
- It requires a `PLUGIN_WORKFLOW_DISPATCH_TOKEN` secret; see the
  [manual setup](upgrade_all_intellij_plugins/README.md#manual-setup-required)
  section.

## Dependabot

[`.github/dependabot.yml`](.github/dependabot.yml) keeps GitHub Actions (`/`) and
pip (`/update_plugins_for_new_jetbrains_release`) dependencies up to date daily.
The pip directory is nested because that is where this repository's
`requirements.txt` actually lives.

[`.github/workflows/dependabot-auto-approve.yml`](.github/workflows/dependabot-auto-approve.yml)
approves authentic Dependabot pull requests. It:

- verifies the PR **author** is `dependabot[bot]` and that the head branch is in
  **this** repository (never a fork) - titles and labels are not trusted,
- **never checks out or executes** pull request code, despite using
  `pull_request_target`,
- uses only `pull-requests: write` with the repository `GITHUB_TOKEN`,
- approves once, and does not merge, bypass checks, or disable protections.

### Manual setup required for approvals

- Enable **Settings → Actions → General → "Allow GitHub Actions to create and
  approve pull requests"**. Without it, `gh pr review --approve` fails.
- If an organisation/enterprise policy restricts Actions or PR approvals by
  automation, the workflow cannot approve until that policy allows it.

### Deviation from the shared template

`github-repo-files-sync` ships `github/workflows/dependabot-auto-merge.yml`,
which enables **auto-merge** but never submits an approving review. Since the
request here was for genuine approval, this repository ships an *approval*
workflow instead. Auto-merge was intentionally **not** copied: this repository
currently has *Allow auto-merge* disabled, so the template's `gh pr merge --auto`
would fail. To add auto-merge later, enable **Settings → General → "Allow
auto-merge"** first, and add a separate step/workflow for it.

### Not synchronised from `github-repo-files-sync`

`ChrisCarini/jetbrains-plugin-scripts` is **not** listed in any group of
[`ChrisCarini/github-repo-files-sync`](https://github.com/ChrisCarini/github-repo-files-sync)'s
`sync.yml`. Neither the Dependabot configuration nor the Dependabot PR workflow
in this repository is automatically synchronised; both are maintained here.

If this repository is enrolled in a sync group later, the generic synced
`dependabot.yml` / `dependabot-auto-merge.yml` would **overwrite** the
customisations above (the nested pip path and the approval logic).

## Development

```bash
shellcheck upgrade_all_intellij_plugins/dispatch-intellij-upgrade.sh \
           upgrade_all_intellij_plugins/tests/test_dispatch_intellij_upgrade.sh
yamllint --strict -c .yamllint.yml .github upgrade_all_intellij_plugins
./upgrade_all_intellij_plugins/tests/test_dispatch_intellij_upgrade.sh
```

The tests mock the `gh` CLI entirely: they never call the GitHub API, never
dispatch a workflow and never review or merge a pull request. The same three
commands run in CI via
[`.github/workflows/lint-and-test.yml`](.github/workflows/lint-and-test.yml).

## GitHub Actions pinning convention

Every `uses:` entry in this repository is pinned to a full 40-character commit
SHA with a full-semver comment, e.g.:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

Dependabot's `github-actions` ecosystem updates both the SHA and the comment.

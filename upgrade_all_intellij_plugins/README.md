# Upgrade the IntelliJ Platform version in all plugin repositories

A **manual** "upgrade everything now" button for the JetBrains plugin
repositories, for the times when a new IntelliJ release shows up before the
daily schedules in each plugin repository notice it.

## Architecture / separation of responsibilities

| Where | Responsibility |
| --- | --- |
| Each plugin repository's `.github/workflows/update-plugin-platform-version.yml` | **Does the upgrade.** Runs daily on a schedule, and also supports `workflow_dispatch`. It fetches the new IntelliJ version, edits the plugin and opens its PR (via `ChrisCarini/gh-test-ij-release-update-action`, using that repository's own `PAT_TOKEN_FOR_IJ_UPDATE_ACTION`). |
| [`ChrisCarini/github-repo-files-sync`](https://github.com/ChrisCarini/github-repo-files-sync) | **Distributes** that workflow to each plugin repository. |
| This directory | **Only triggers** the workflow above, once per selected repository. |

This dispatcher deliberately contains **no** upgrade logic: it never queries the
IntelliJ release feed and never edits a downstream repository's code. The daily
schedules in the plugin repositories remain the fallback and are untouched.

## Contents

| File | Purpose |
| --- | --- |
| [`plugin-repos.txt`](plugin-repos.txt) | Explicit allowlist of dispatchable repositories. |
| [`dispatch-intellij-upgrade.sh`](dispatch-intellij-upgrade.sh) | Validation + dispatch + reporting. |
| [`tests/test_dispatch_intellij_upgrade.sh`](tests/test_dispatch_intellij_upgrade.sh) | Fully mocked tests (no network, no dispatch). |
| [`../.github/workflows/upgrade-all-intellij-plugins.yml`](../.github/workflows/upgrade-all-intellij-plugins.yml) | `workflow_dispatch`-only wrapper. |

## Allowlist: provenance, maintenance and coverage limits

`plugin-repos.txt` was seeded from the *JetBrains Plugin - Build & Release* group
of `github-repo-files-sync`'s `sync.yml` - the group that actually distributes
`update-plugin-platform-version.yml`. Repositories are **not** selected because
their name contains `intellij` or `jetbrains`.

Coverage limits worth knowing:

- **The allowlist is a manually maintained copy.** It is not generated from, or
  synchronised with, `sync.yml`. When a plugin is added to (or removed from)
  that sync group, update `plugin-repos.txt` in the same spirit.
- Membership in the allowlist is **necessary but not sufficient**. Every run
  re-validates each repository live before dispatching (see below), so a repo
  that has been archived, renamed, or lost its workflow is reported as a failure
  rather than silently dispatched.
- `ChrisCarini/jetbrains-error-utils` is in some other sync groups but *not* in
  the platform-version group, so it is intentionally absent here.

## Validation performed for every target

Before anything is dispatched, the *whole selection* is validated and rejected
as a unit if any entry is bad:

1. matches `owner/repo`,
2. owner is `ChrisCarini`,
3. is present in the allowlist,
4. duplicates are collapsed.

Then, per repository (read-only API calls):

5. the repository is readable and still has the expected `full_name`
   (i.e. it was not renamed/transferred),
6. it is neither archived nor disabled,
7. its **actual** default branch is resolved - `main` is never assumed,
8. `update-plugin-platform-version.yml` exists and its workflow `state` is
   `active`,
9. that workflow's YAML on the default branch declares `workflow_dispatch`.

Only then is `POST /repos/{owner}/{repo}/actions/workflows/{file}/dispatches`
sent, with `ref` set to that repository's real default branch.

## Dry run first

`dry_run` defaults to **`true`**. A dry run performs every validation above and
prints/summarises exactly what *would* be dispatched, while sending **zero**
write requests. Run it first; only set `dry_run: false` when the summary looks
right.

## Usage

### From the GitHub UI

*Actions → "Upgrade IntelliJ Platform version in all plugin repositories" → Run
workflow*, then:

| Input | Value |
| --- | --- |
| `targets` | `all` (default), or e.g. `ChrisCarini/logshipper-intellij-plugin, ChrisCarini/iris-jetbrains-plugin` |
| `dry_run` | leave checked to validate; uncheck to actually dispatch |

### From the CLI

```bash
# Dry run against every allowlisted repository
gh workflow run upgrade-all-intellij-plugins.yml \
  --repo ChrisCarini/jetbrains-plugin-scripts

# Dry run against a subset
gh workflow run upgrade-all-intellij-plugins.yml \
  --repo ChrisCarini/jetbrains-plugin-scripts \
  -f targets='ChrisCarini/logshipper-intellij-plugin,ChrisCarini/iris-jetbrains-plugin'

# For real, all repositories
gh workflow run upgrade-all-intellij-plugins.yml \
  --repo ChrisCarini/jetbrains-plugin-scripts \
  -f dry_run=false
```

### Locally

```bash
GH_TOKEN=<token with Actions: write on the targets> \
  ./upgrade_all_intellij_plugins/dispatch-intellij-upgrade.sh            # dry run, all

DRY_RUN=false ./upgrade_all_intellij_plugins/dispatch-intellij-upgrade.sh \
  ChrisCarini/logshipper-intellij-plugin
```

Environment variables: `TARGETS`, `DRY_RUN`, `ALLOWLIST_FILE`, `WORKFLOW_FILE`,
`GH_TIMEOUT`, `GH_TOKEN`. Requires `gh`, `jq` and `timeout`.

## Output semantics and exit status

Every selected repository is attempted **independently**: one failure does not
stop the rest. Results are printed to the log and rendered as a GitHub step
summary table.

| Result | Meaning |
| --- | --- |
| `dispatched` | The GitHub API **accepted** the dispatch request. |
| `dry-run` | Validated only; nothing was sent. |
| `failed` | Validation or the dispatch request failed; the log line says why. |

| Exit code | Meaning |
| --- | --- |
| `0` | Everything succeeded (or validated, in dry run). |
| `1` | At least one repository failed. |
| `2` | The selection itself was invalid - **nothing was dispatched**. |

Important: *dispatched* means only that the downstream workflow was **queued**.
It says nothing about whether the upgrade itself succeeded - check the run in
the plugin repository for that. The dispatch API returns `204 No Content` with
no run identifier, so this script deliberately does **not** print run URLs
rather than inventing them.

Requests are never retried, because a retried `POST` can start a duplicate run.
Each `gh` call is bounded by `GH_TIMEOUT` (default 60s), the job has a 20 minute
timeout, and a `concurrency` group prevents two dispatch rounds overlapping.

## Manual setup required

Merging this PR **does not** provision anything. To make the workflow usable:

1. **Create a token.** A fine-grained PAT is the simplest option:
   - *Repository access*: only the repositories in `plugin-repos.txt`.
   - *Repository permissions*:
     - **Actions: Read and write** - required to dispatch, and to read the
       workflow's `state`.
     - **Contents: Read-only** - required to read the workflow YAML (to confirm
       `workflow_dispatch`) and the repository metadata.
   - No other permission is needed: the dispatcher never writes plugin files and
     never opens PRs.
   - A GitHub App installation token with the same two permissions works too,
     and is the better option if you want rotation/auditing.
2. **Store it** in this repository as the secret
   **`PLUGIN_WORKFLOW_DISPATCH_TOKEN`**. Keep it separate from the downstream
   `PAT_TOKEN_FOR_IJ_UPDATE_ACTION`, which the plugin repositories use for their
   own commits/PRs.
3. **Downstream prerequisites** (already true for the seeded allowlist): each
   target keeps `.github/workflows/update-plugin-platform-version.yml` on its
   default branch, with Actions enabled, the workflow active, `workflow_dispatch`
   declared, and its own `PAT_TOKEN_FOR_IJ_UPDATE_ACTION` secret set.

The dispatcher job itself runs with `permissions: {}` and checks out the code
with `persist-credentials: false`; no secret is exposed to any pull-request
triggered job.

## Not synchronised

`ChrisCarini/jetbrains-plugin-scripts` does **not** appear in any group of
`github-repo-files-sync`'s `sync.yml`. Everything here - this dispatcher, the
Dependabot configuration and the Dependabot approval workflow - is maintained
**locally in this repository** and will not be updated by the sync automation.

If you later enrol this repository into a sync group, be aware that a generic
synced file would **overwrite** the customisations here (most notably the
approval workflow, which differs from the shared auto-merge template).

#!/usr/bin/env bash

##
# Manually dispatch the *existing* `update-plugin-platform-version.yml` workflow
# in each selected JetBrains plugin repository.
#
# This script never fetches IntelliJ versions and never edits downstream code;
# all upgrade logic lives in each plugin repo's own workflow.
#
# Configuration is read from the environment (never interpolated by the caller
# into a shell string):
#   TARGETS         Comma/whitespace/newline separated `owner/repo` list, or
#                   `all` (default) to select every allowlisted repository.
#   DRY_RUN         `true` (default) validates only and performs ZERO writes.
#                   `false` actually dispatches.
#   ALLOWLIST_FILE  Defaults to `plugin-repos.txt` next to this script.
#   WORKFLOW_FILE   Workflow to dispatch. Defaults to
#                   `update-plugin-platform-version.yml`.
#   GH_TIMEOUT      Per-`gh`-invocation timeout in seconds (default 60).
#   GH_TOKEN        Token with `Actions: write` (+ `Contents: read`) on the
#                   targets. Required unless `gh` is already authenticated.
#
# Positional arguments, if given, are an alternative to `TARGETS`.
#
# Exit status: 0 all selected targets succeeded (or validated, in dry-run),
#              2 the selection itself was invalid (nothing was dispatched),
#              1 at least one target failed.
##

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

ALLOWLIST_FILE="${ALLOWLIST_FILE:-${SCRIPT_DIR}/plugin-repos.txt}"
WORKFLOW_FILE="${WORKFLOW_FILE:-update-plugin-platform-version.yml}"
REQUIRED_OWNER="ChrisCarini"
GH_TIMEOUT="${GH_TIMEOUT:-60}"

# `owner/repo`, using the character set GitHub actually allows for repo names.
REPO_REGEX='^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$'

log() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

##
# Append a line to the GitHub step summary, when running inside GitHub Actions.
##
summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$*" >>"${GITHUB_STEP_SUMMARY}"
  fi
}

##
# Run `gh` with a bounded timeout. Never retried: a retried POST could start a
# duplicate workflow run.
##
gh_run() {
  timeout "${GH_TIMEOUT}" gh "$@"
}

##
# Read the allowlist into the `allowlist` array, validating every entry.
##
read_allowlist() {
  local line
  allowlist=()
  if [[ ! -f "${ALLOWLIST_FILE}" ]]; then
    err "Allowlist file not found: ${ALLOWLIST_FILE}"
    exit 2
  fi
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    # Trim surrounding whitespace.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "${line}" ]] && continue
    if [[ ! "${line}" =~ ${REPO_REGEX} ]]; then
      err "Malformed entry in ${ALLOWLIST_FILE}: '${line}'"
      exit 2
    fi
    if [[ "${line%%/*}" != "${REQUIRED_OWNER}" ]]; then
      err "Entry in ${ALLOWLIST_FILE} is not owned by ${REQUIRED_OWNER}: '${line}'"
      exit 2
    fi
    allowlist+=("${line}")
  done <"${ALLOWLIST_FILE}"

  if [[ "${#allowlist[@]}" -eq 0 ]]; then
    err "Allowlist ${ALLOWLIST_FILE} contains no repositories."
    exit 2
  fi
}

##
# Resolve the requested selection into the `targets` array. Every problem is
# collected and reported, and nothing is dispatched if any problem was found.
##
resolve_targets() {
  local raw="$1"
  local -a requested=()
  local -a problems=()
  local candidate allowed seen found

  if [[ -z "${raw}" || "${raw}" == "all" ]]; then
    targets=("${allowlist[@]}")
    log "Selection: all ${#targets[@]} allowlisted repositories."
    return 0
  fi

  # Split on commas and any whitespace; no `eval`, no word-splitting surprises.
  IFS=$', \t\n\r' read -r -d '' -a requested < <(printf '%s\0' "${raw}") || true

  targets=()
  for candidate in "${requested[@]:-}"; do
    [[ -z "${candidate}" ]] && continue

    if [[ "${candidate}" == "all" ]]; then
      problems+=("'all' cannot be combined with explicit repositories.")
      continue
    fi
    if [[ ! "${candidate}" =~ ${REPO_REGEX} ]]; then
      problems+=("Not a valid 'owner/repo' value: '${candidate}'")
      continue
    fi
    if [[ "${candidate%%/*}" != "${REQUIRED_OWNER}" ]]; then
      problems+=("Repository is not owned by ${REQUIRED_OWNER}: '${candidate}'")
      continue
    fi

    found="false"
    for allowed in "${allowlist[@]}"; do
      if [[ "${candidate}" == "${allowed}" ]]; then
        found="true"
        break
      fi
    done
    if [[ "${found}" != "true" ]]; then
      problems+=("Repository is not in the allowlist: '${candidate}'")
      continue
    fi

    # De-duplicate, keeping the first occurrence.
    seen="false"
    for allowed in "${targets[@]:-}"; do
      if [[ "${candidate}" == "${allowed}" ]]; then
        seen="true"
        break
      fi
    done
    if [[ "${seen}" == "true" ]]; then
      log "Ignoring duplicate selection of ${candidate}."
      continue
    fi

    targets+=("${candidate}")
  done

  if [[ "${#problems[@]}" -gt 0 ]]; then
    err "Invalid selection; nothing was dispatched:"
    for candidate in "${problems[@]}"; do
      err "  - ${candidate}"
    done
    exit 2
  fi

  if [[ "${#targets[@]}" -eq 0 ]]; then
    err "No repositories selected."
    exit 2
  fi

  log "Selection: ${#targets[@]} repository/repositories."
}

##
# Validate a single target against the live GitHub API.
# Echoes the default branch on success; returns non-zero with a reason on
# stderr otherwise. Performs read-only requests only.
##
validate_target() {
  local repo="$1"
  local repo_json default_branch workflow_json workflow_state workflow_yaml

  if ! repo_json="$(gh_run api "repos/${repo}" 2>&1)"; then
    err "Cannot read repository ${repo}: ${repo_json}"
    return 1
  fi

  local full_name archived disabled
  full_name="$(printf '%s' "${repo_json}" | jq -r '.full_name // empty')"
  archived="$(printf '%s' "${repo_json}" | jq -r '.archived // false')"
  disabled="$(printf '%s' "${repo_json}" | jq -r '.disabled // false')"
  default_branch="$(printf '%s' "${repo_json}" | jq -r '.default_branch // empty')"

  if [[ "${full_name}" != "${repo}" ]]; then
    err "Repository ${repo} resolved to '${full_name}' (renamed or moved); refusing to dispatch."
    return 1
  fi
  if [[ "${archived}" == "true" ]]; then
    err "Repository ${repo} is archived."
    return 1
  fi
  if [[ "${disabled}" == "true" ]]; then
    err "Repository ${repo} is disabled."
    return 1
  fi
  if [[ -z "${default_branch}" ]]; then
    err "Could not determine the default branch of ${repo}."
    return 1
  fi

  if ! workflow_json="$(gh_run api "repos/${repo}/actions/workflows/${WORKFLOW_FILE}" 2>&1)"; then
    err "Workflow ${WORKFLOW_FILE} not found (or Actions not readable) in ${repo}: ${workflow_json}"
    return 1
  fi
  workflow_state="$(printf '%s' "${workflow_json}" | jq -r '.state // empty')"
  if [[ "${workflow_state}" != "active" ]]; then
    err "Workflow ${WORKFLOW_FILE} in ${repo} is not active (state: ${workflow_state:-unknown})."
    return 1
  fi

  if ! workflow_yaml="$(gh_run api \
    -H "Accept: application/vnd.github.raw" \
    "repos/${repo}/contents/.github/workflows/${WORKFLOW_FILE}?ref=${default_branch}" 2>&1)"; then
    err "Cannot read ${WORKFLOW_FILE} on ${repo}@${default_branch}: ${workflow_yaml}"
    return 1
  fi
  if ! printf '%s\n' "${workflow_yaml}" | grep -Eq '^[[:space:]]*workflow_dispatch:?[[:space:]]*$'; then
    err "Workflow ${WORKFLOW_FILE} on ${repo}@${default_branch} does not declare 'workflow_dispatch'."
    return 1
  fi

  printf '%s' "${default_branch}"
}

main() {
  local raw_targets="${TARGETS:-all}"
  if [[ "$#" -gt 0 ]]; then
    raw_targets="$*"
  fi

  local dry_run="${DRY_RUN:-true}"
  case "${dry_run}" in
    true | false) ;;
    *)
      err "DRY_RUN must be 'true' or 'false' (got '${dry_run}')."
      exit 2
      ;;
  esac

  local dep
  for dep in gh jq timeout; do
    if ! command -v "${dep}" >/dev/null 2>&1; then
      err "Required dependency '${dep}' is not installed."
      exit 2
    fi
  done

  local -a allowlist=() targets=()
  read_allowlist
  resolve_targets "${raw_targets}"

  if [[ "${dry_run}" == "true" ]]; then
    log "DRY RUN: validating only. No dispatch requests will be sent."
  else
    log "LIVE RUN: validated repositories will be dispatched."
  fi
  log ""

  local -a results=()
  local repo default_branch failures=0 dispatched=0 validated=0

  for repo in "${targets[@]}"; do
    log "--- ${repo}"
    if ! default_branch="$(validate_target "${repo}")"; then
      results+=("${repo}|:x: failed|-|validation failed (see log)")
      failures=$((failures + 1))
      log ""
      continue
    fi
    log "Validated ${repo} (default branch: ${default_branch}, workflow: ${WORKFLOW_FILE})."

    if [[ "${dry_run}" == "true" ]]; then
      log "Would dispatch ${WORKFLOW_FILE} on ${repo}@${default_branch}."
      results+=("${repo}|:mag: dry-run|${default_branch}|validated; no request sent")
      validated=$((validated + 1))
      log ""
      continue
    fi

    local dispatch_output
    if dispatch_output="$(gh_run api --method POST \
      "repos/${repo}/actions/workflows/${WORKFLOW_FILE}/dispatches" \
      -f "ref=${default_branch}" 2>&1)"; then
      log "Dispatch accepted by the GitHub API for ${repo}@${default_branch}."
      results+=("${repo}|:white_check_mark: dispatched|${default_branch}|API accepted the dispatch")
      dispatched=$((dispatched + 1))
    else
      err "Dispatch failed for ${repo}@${default_branch}: ${dispatch_output}"
      results+=("${repo}|:x: failed|${default_branch}|dispatch request failed")
      failures=$((failures + 1))
    fi
    log ""
  done

  local mode_label="Live run"
  [[ "${dry_run}" == "true" ]] && mode_label="Dry run"

  summary "## IntelliJ plugin upgrade dispatcher"
  summary ""
  summary "**Mode:** ${mode_label} &nbsp;&nbsp; **Workflow:** \`${WORKFLOW_FILE}\`"
  summary ""
  summary "| Repository | Result | Ref | Detail |"
  summary "| --- | --- | --- | --- |"

  local row
  for row in "${results[@]}"; do
    IFS='|' read -r r_repo r_status r_ref r_detail <<<"${row}"
    summary "| \`${r_repo}\` | ${r_status} | \`${r_ref}\` | ${r_detail} |"
  done

  summary ""
  summary "Dispatched: ${dispatched} &nbsp;&nbsp; Dry-run validated: ${validated} &nbsp;&nbsp; Failed: ${failures}"
  summary ""
  summary "> An accepted dispatch only means the GitHub API queued the downstream workflow."
  summary "> Check each plugin repository's own workflow run for the upgrade outcome."

  log "Summary: dispatched=${dispatched} dry-run-validated=${validated} failed=${failures}"

  if [[ "${failures}" -gt 0 ]]; then
    err "${failures} repository/repositories failed."
    exit 1
  fi
}

main "$@"

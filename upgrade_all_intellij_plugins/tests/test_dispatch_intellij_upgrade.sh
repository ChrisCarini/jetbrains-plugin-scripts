#!/usr/bin/env bash

##
# Isolated tests for `dispatch-intellij-upgrade.sh`.
#
# Everything is mocked: a fake `gh` is placed first on `PATH`, so no network
# request, no dispatch and no pull request review is ever performed.
#
# Usage: ./upgrade_all_intellij_plugins/tests/test_dispatch_intellij_upgrade.sh
##

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SCRIPT_UNDER_TEST="${TESTS_DIR}/../dispatch-intellij-upgrade.sh"
REPO_ROOT="$(cd "${TESTS_DIR}/../.." >/dev/null 2>&1 && pwd)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

tests_run=0
tests_failed=0

pass() {
  tests_run=$((tests_run + 1))
  printf 'ok   - %s\n' "$1"
}

fail() {
  tests_run=$((tests_run + 1))
  tests_failed=$((tests_failed + 1))
  printf 'FAIL - %s\n' "$1"
  if [[ -n "${2:-}" ]]; then
    printf '       %s\n' "$2"
  fi
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    pass "${name}"
  else
    fail "${name}" "expected '${expected}', got '${actual}'"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    pass "${name}"
  else
    fail "${name}" "expected output to contain '${needle}'"
  fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    pass "${name}"
  else
    fail "${name}" "expected output NOT to contain '${needle}'"
  fi
}

##
# Create a sandbox with a mocked `gh` on PATH.
#
# The mock is driven by files in the sandbox:
#   repos/<owner>__<repo>.json    fake `repos/<owner>/<repo>` payload
#   workflows/<owner>__<repo>.json fake workflow payload
#   contents/<owner>__<repo>.yml  fake workflow YAML
#   fail-dispatch                 newline separated repos whose POST fails
# and records every invocation in `gh-calls.log`.
##
new_sandbox() {
  SANDBOX="$(mktemp -d "${TMP_ROOT}/sandbox.XXXXXX")"
  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/repos" "${SANDBOX}/workflows" "${SANDBOX}/contents"
  : >"${SANDBOX}/gh-calls.log"
  : >"${SANDBOX}/fail-dispatch"

  cat >"${SANDBOX}/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail

printf '%s\n' "$*" >>"${SANDBOX}/gh-calls.log"

path=""
method="GET"
for arg in "$@"; do
  case "${arg}" in
    api | -H | -f | --method | Accept:*) continue ;;
    POST) method="POST" ;;
    ref=*) continue ;;
    *) [[ -z "${path}" ]] && path="${arg}" ;;
  esac
done

# Strip any `?ref=...` query string.
path="${path%%\?*}"

slug_of() {
  # `repos/<owner>/<repo>/...` -> `<owner>__<repo>`
  local p="${1#repos/}"
  printf '%s__%s' "${p%%/*}" "$(printf '%s' "${p#*/}" | cut -d'/' -f1)"
}

slug="$(slug_of "${path}")"

if [[ "${method}" == "POST" ]]; then
  if grep -Fxq "${slug}" "${SANDBOX}/fail-dispatch" 2>/dev/null; then
    echo "mock: dispatch rejected for ${slug}" >&2
    exit 1
  fi
  exit 0
fi

case "${path}" in
  repos/*/*/actions/workflows/*)
    file="${SANDBOX}/workflows/${slug}.json"
    ;;
  repos/*/*/contents/*)
    file="${SANDBOX}/contents/${slug}.yml"
    ;;
  repos/*/*)
    file="${SANDBOX}/repos/${slug}.json"
    ;;
  *)
    echo "mock: unexpected path '${path}'" >&2
    exit 1
    ;;
esac

if [[ ! -f "${file}" ]]; then
  echo "mock: 404 Not Found (${path})" >&2
  exit 1
fi
cat "${file}"
MOCK
  chmod +x "${SANDBOX}/bin/gh"

  ALLOWLIST="${SANDBOX}/allowlist.txt"
  cat >"${ALLOWLIST}" <<'EOF'
# comment line
ChrisCarini/alpha-intellij-plugin

ChrisCarini/beta-intellij-plugin
ChrisCarini/gamma-intellij-plugin
EOF

  mock_repo ChrisCarini/alpha-intellij-plugin main
  mock_repo ChrisCarini/beta-intellij-plugin trunk
  mock_repo ChrisCarini/gamma-intellij-plugin main
}

##
# Register a healthy, dispatchable repository in the sandbox.
##
mock_repo() {
  local repo="$1" branch="$2" slug
  slug="${repo/\//__}"
  cat >"${SANDBOX}/repos/${slug}.json" <<EOF
{"full_name": "${repo}", "archived": false, "disabled": false, "default_branch": "${branch}"}
EOF
  cat >"${SANDBOX}/workflows/${slug}.json" <<'EOF'
{"state": "active", "path": ".github/workflows/update-plugin-platform-version.yml"}
EOF
  cat >"${SANDBOX}/contents/${slug}.yml" <<'EOF'
name: 'Update JetBrains Plugin Platform Version'
on:
  schedule:
    - cron: "0 0 * * *"

  workflow_dispatch:
EOF
}

##
# Run the script under test inside the sandbox.
# Sets: OUTPUT, STATUS, SUMMARY
##
run_script() {
  SUMMARY_FILE="${SANDBOX}/summary.md"
  : >"${SUMMARY_FILE}"
  OUTPUT="$(
    env SANDBOX="${SANDBOX}" \
      PATH="${SANDBOX}/bin:${PATH}" \
      ALLOWLIST_FILE="${ALLOWLIST}" \
      GITHUB_STEP_SUMMARY="${SUMMARY_FILE}" \
      "$@" "${SCRIPT_UNDER_TEST}" 2>&1
  )"
  STATUS=$?
  SUMMARY="$(cat "${SUMMARY_FILE}")"
}

gh_calls() { cat "${SANDBOX}/gh-calls.log"; }

#############################################
# Test: default selection is all + dry run
#############################################
new_sandbox
run_script
assert_eq "default selection exits 0" 0 "${STATUS}"
assert_contains "default selection selects all" "${OUTPUT}" "Selection: all 3 allowlisted repositories."
assert_contains "default mode is dry run" "${OUTPUT}" "DRY RUN"
assert_eq "dry run performs zero writes" "0" "$(gh_calls | grep -c -- '--method POST' || true)"
assert_contains "dry run summarises all three" "${OUTPUT}" "dry-run-validated=3"
assert_contains "summary is written" "${SUMMARY}" "IntelliJ plugin upgrade dispatcher"
assert_contains "summary contains dry-run row" "${SUMMARY}" "dry-run"

#############################################
# Test: explicit 'all'
#############################################
new_sandbox
run_script TARGETS=all
assert_eq "'all' exits 0" 0 "${STATUS}"
assert_contains "'all' selects everything" "${OUTPUT}" "Selection: all 3 allowlisted repositories."

#############################################
# Test: subset selection
#############################################
new_sandbox
run_script TARGETS="ChrisCarini/beta-intellij-plugin, ChrisCarini/gamma-intellij-plugin"
assert_eq "subset exits 0" 0 "${STATUS}"
assert_contains "subset size" "${OUTPUT}" "Selection: 2 repository/repositories."
assert_not_contains "subset excludes alpha" "${OUTPUT}" "alpha-intellij-plugin"

#############################################
# Test: duplicate targets are de-duplicated
#############################################
new_sandbox
run_script TARGETS="ChrisCarini/beta-intellij-plugin,ChrisCarini/beta-intellij-plugin"
assert_eq "duplicates exit 0" 0 "${STATUS}"
assert_contains "duplicate is reported" "${OUTPUT}" "Ignoring duplicate selection"
assert_contains "duplicate collapses to one" "${OUTPUT}" "Selection: 1 repository/repositories."

#############################################
# Test: input rejection
#############################################
new_sandbox
run_script TARGETS="someoneelse/intellij-plugin"
assert_eq "foreign owner rejected" 2 "${STATUS}"
assert_contains "foreign owner reason" "${OUTPUT}" "not owned by ChrisCarini"

new_sandbox
run_script TARGETS="ChrisCarini/not-allowlisted"
assert_eq "unknown target rejected" 2 "${STATUS}"
assert_contains "unknown target reason" "${OUTPUT}" "not in the allowlist"

new_sandbox
run_script TARGETS='ChrisCarini/alpha-intellij-plugin;rm -rf /'
assert_eq "injected input rejected" 2 "${STATUS}"
assert_contains "injected input reason" "${OUTPUT}" "Not a valid 'owner/repo' value"
assert_eq "invalid selection performs no API calls" "0" "$(gh_calls | wc -l | tr -d ' ')"

new_sandbox
run_script TARGETS="all,ChrisCarini/alpha-intellij-plugin"
assert_eq "'all' plus explicit rejected" 2 "${STATUS}"

new_sandbox
run_script DRY_RUN=maybe
assert_eq "invalid DRY_RUN rejected" 2 "${STATUS}"
assert_contains "invalid DRY_RUN reason" "${OUTPUT}" "DRY_RUN must be"

#############################################
# Test: live run dispatches each target's real default branch
#############################################
new_sandbox
run_script DRY_RUN=false
assert_eq "live run exits 0" 0 "${STATUS}"
assert_eq "live run dispatches every target" "3" "$(gh_calls | grep -c -- '--method POST' || true)"
assert_contains "non-main default branch used" "$(gh_calls)" "ref=trunk"
assert_contains "main default branch used" "$(gh_calls)" "ref=main"
assert_contains "live run summary" "${OUTPUT}" "dispatched=3"
assert_contains "summary distinguishes API acceptance" "${SUMMARY}" "API accepted the dispatch"

#############################################
# Test: continuation after a dispatch failure
#############################################
new_sandbox
echo "ChrisCarini__beta-intellij-plugin" >"${SANDBOX}/fail-dispatch"
run_script DRY_RUN=false
assert_eq "dispatch failure exits 1" 1 "${STATUS}"
assert_eq "other targets still attempted" "3" "$(gh_calls | grep -c -- '--method POST' || true)"
assert_contains "failure counted" "${OUTPUT}" "dispatched=2"
assert_contains "failure counted in summary" "${OUTPUT}" "failed=1"

#############################################
# Test: inaccessible / archived repositories
#############################################
new_sandbox
rm "${SANDBOX}/repos/ChrisCarini__gamma-intellij-plugin.json"
run_script DRY_RUN=false
assert_eq "inaccessible repo exits 1" 1 "${STATUS}"
assert_contains "inaccessible repo reason" "${OUTPUT}" "Cannot read repository ChrisCarini/gamma-intellij-plugin"
assert_eq "healthy repos still dispatched" "2" "$(gh_calls | grep -c -- '--method POST' || true)"

new_sandbox
cat >"${SANDBOX}/repos/ChrisCarini__alpha-intellij-plugin.json" <<'EOF'
{"full_name": "ChrisCarini/alpha-intellij-plugin", "archived": true, "disabled": false, "default_branch": "main"}
EOF
run_script TARGETS="ChrisCarini/alpha-intellij-plugin" DRY_RUN=false
assert_eq "archived repo exits 1" 1 "${STATUS}"
assert_contains "archived repo reason" "${OUTPUT}" "is archived"
assert_eq "archived repo not dispatched" "0" "$(gh_calls | grep -c -- '--method POST' || true)"

new_sandbox
cat >"${SANDBOX}/repos/ChrisCarini__alpha-intellij-plugin.json" <<'EOF'
{"full_name": "ChrisCarini/renamed-plugin", "archived": false, "disabled": false, "default_branch": "main"}
EOF
run_script TARGETS="ChrisCarini/alpha-intellij-plugin" DRY_RUN=false
assert_eq "renamed repo exits 1" 1 "${STATUS}"
assert_contains "renamed repo reason" "${OUTPUT}" "renamed or moved"

#############################################
# Test: missing / disabled / non-dispatchable workflow
#############################################
new_sandbox
rm "${SANDBOX}/workflows/ChrisCarini__alpha-intellij-plugin.json"
run_script TARGETS="ChrisCarini/alpha-intellij-plugin" DRY_RUN=false
assert_eq "missing workflow exits 1" 1 "${STATUS}"
assert_contains "missing workflow reason" "${OUTPUT}" "not found"

new_sandbox
cat >"${SANDBOX}/workflows/ChrisCarini__alpha-intellij-plugin.json" <<'EOF'
{"state": "disabled_manually", "path": ".github/workflows/update-plugin-platform-version.yml"}
EOF
run_script TARGETS="ChrisCarini/alpha-intellij-plugin" DRY_RUN=false
assert_eq "disabled workflow exits 1" 1 "${STATUS}"
assert_contains "disabled workflow reason" "${OUTPUT}" "is not active"
assert_eq "disabled workflow not dispatched" "0" "$(gh_calls | grep -c -- '--method POST' || true)"

new_sandbox
cat >"${SANDBOX}/contents/ChrisCarini__alpha-intellij-plugin.yml" <<'EOF'
name: 'Update JetBrains Plugin Platform Version'
on:
  schedule:
    - cron: "0 0 * * *"
EOF
run_script TARGETS="ChrisCarini/alpha-intellij-plugin" DRY_RUN=false
assert_eq "non-dispatchable workflow exits 1" 1 "${STATUS}"
assert_contains "non-dispatchable reason" "${OUTPUT}" "does not declare 'workflow_dispatch'"
assert_eq "non-dispatchable not dispatched" "0" "$(gh_calls | grep -c -- '--method POST' || true)"

#############################################
# Test: dry run validates failures too, with zero writes
#############################################
new_sandbox
rm "${SANDBOX}/workflows/ChrisCarini__beta-intellij-plugin.json"
run_script
assert_eq "dry run reports failures" 1 "${STATUS}"
assert_eq "dry run still performs zero writes" "0" "$(gh_calls | grep -c -- '--method POST' || true)"
assert_contains "dry run counts" "${OUTPUT}" "dry-run-validated=2"

#############################################
# Test: the shipped allowlist is well formed
#############################################
new_sandbox
ALLOWLIST="${REPO_ROOT}/upgrade_all_intellij_plugins/plugin-repos.txt"
run_script TARGETS="ChrisCarini/definitely-not-a-real-plugin"
assert_eq "shipped allowlist parses" 2 "${STATUS}"
assert_contains "shipped allowlist rejects unknown repo" "${OUTPUT}" "not in the allowlist"

printf '\n%s test(s) run, %s failure(s)\n' "${tests_run}" "${tests_failed}"
[[ "${tests_failed}" -eq 0 ]]

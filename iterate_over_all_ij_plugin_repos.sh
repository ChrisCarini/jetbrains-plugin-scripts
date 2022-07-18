#!/usr/bin/env bash

##
# Run code across all JetBrains plugin code repositories
##

BASE_CODE_PATH=${1:-~/GitHub}
BASE_JB_CODE_PATH="${BASE_CODE_PATH}/jetbrains"
BASE_JB_PLUGINS_CODE_PATH="${BASE_JB_CODE_PATH}/plugins"

function execute_in_repo() {
  REPO=$1
  MAIN_BRANCH=$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')
  echo "Running in repo: ${REPO} (main branch: ${MAIN_BRANCH})"
  add_code_owners "${REPO}" "${MAIN_BRANCH}"
}

function add_code_owners() {
  ##
  # Add CODEOWNERS file (https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
  ##
  REPO=$1
  MAIN_BRANCH=$2

  CHANGE_BRANCH_NAME=ChrisCarini/AddCodeOwner

  CURRENT_BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)

  git stash # Save any pre-existing changes in the repo that have not yet been committed.

  git fetch
  git checkout -b "${CHANGE_BRANCH_NAME}" "origin/${MAIN_BRANCH}"

  mkdir -p .github/ && touch .github/CODEOWNERS

  cat <<EOF >.github/CODEOWNERS
# Docs: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
* @ChrisCarini
EOF

  git add .github/CODEOWNERS
  git commit -m "Adding CODEOWNERS file."
  git push --set-upstream origin "${CHANGE_BRANCH_NAME}"
  gh pr create \
    --title "Adding GitHub CODEOWNERS" \
    --body "Adding GitHub CODEOWNERS file to ${REPO}" \
    --assignee "ChrisCarini" \
    --reviewer "ChrisCarini" \
    --base "${MAIN_BRANCH}" \
    --head "${CHANGE_BRANCH_NAME}"

  # Restore the previous branch, and pop any stashed changes
  git checkout "${CURRENT_BRANCH_NAME}"
  git stash pop
}

##
# JetBrains Plugin Repos
##
jetbrains_plugin_repos=(
  ChrisCarini/environment-variable-settings-summary-intellij-plugin
  ChrisCarini/intellij-code-exfiltration
  ChrisCarini/intellij-notification-sample
  ChrisCarini/iris-jetbrains-plugin
  ChrisCarini/jetbrains-auto-power-saver
#  ChrisCarini/loc-change-count-detector-jetbrains-plugin
  ChrisCarini/logshipper-intellij-plugin
#  ChrisCarini/sample-intellij-plugin
)
pushd "${BASE_JB_PLUGINS_CODE_PATH}" >/dev/null || exit
for REPO in "${jetbrains_plugin_repos[@]}"; do
  CODE_REPO_PATH="${BASE_JB_PLUGINS_CODE_PATH}/$(echo ${REPO} | cut -d'/' -f2)"
  # Check if the directory does not exists; if so, exit
  if [ ! -d "$CODE_REPO_PATH" ]; then
    echo "$CODE_REPO_PATH does not exist; exiting."
    exit 1
  fi
  # shellcheck disable=SC2164
  pushd "${CODE_REPO_PATH}" >/dev/null
  echo "Repo [ Processing ]: ${CODE_REPO_PATH}"
  execute_in_repo "${REPO}"
  echo "Repo [  Complete  ]: ${CODE_REPO_PATH}"
  # shellcheck disable=SC2164
  popd >/dev/null
  echo # newline makes output easier to read
done
popd >/dev/null || exit

##
# Misc JetBrains Repos
##
jetbrains_misc_repos=(
    ChrisCarini/intellij-platform-plugin-verifier-action
    ChrisCarini/jetbrains-ide-release-dates
    ChrisCarini/jetbrains-plugin-scripts
    ChrisCarini/jetbrains.chriscarini.com
)
pushd "${BASE_JB_CODE_PATH}" >/dev/null || exit
for REPO in "${jetbrains_misc_repos[@]}"; do
  CODE_REPO_PATH="${BASE_JB_CODE_PATH}/$(echo ${REPO} | cut -d'/' -f2)"
  # Check if the directory does not exists; if so, exit
  if [ ! -d "$CODE_REPO_PATH" ]; then
    echo "$CODE_REPO_PATH does not exist; exiting."
    exit 1
  fi
  # shellcheck disable=SC2164
  pushd "${CODE_REPO_PATH}" >/dev/null
  echo "Repo [ Processing ]: ${CODE_REPO_PATH}"
  execute_in_repo "${REPO}"
  echo "Repo [  Complete  ]: ${CODE_REPO_PATH}"
  # shellcheck disable=SC2164
  popd >/dev/null
  echo # newline makes output easier to read
done

popd >/dev/null || exit

#!/bin/bash
###########################################################################
# Instructions:
#   1) `cd` into the directory containing JetBrains plugins (ie, `~/GitHub/jetbrains/plugins`)
#   2) Run: ../jetbrains-plugin-scripts/03-configure_update_gradle_wrapper_github_action.sh
###########################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GITHUB_USERNAME=ChrisCarini

for d in */; do
  echo "============================================"
  echo "Processing ${d}"

  pushd "${d}"

  ##
  # Create the branch we will use
  ##
  MAIN_BRANCH="$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')"
  GITHUB_BRANCH="${GITHUB_USERNAME}/updateGradleWrapperGHAction"
  git checkout "${MAIN_BRANCH}" && git pull
  git checkout -b "${GITHUB_BRANCH}"

  ##
  # Install Automerge & Freshness guardian (https://go/github/docs/ci-settings)
  ##
  mkdir -p .github/ && touch .github/dependabot.yml

  cat <<"EOF" | perl -pe 'chomp if eof' >.github/workflows/update-gradle-wrapper.yml
name: Update Gradle Wrapper

on:
  schedule:
    - cron: "0 0 * * *"

  workflow_dispatch:


jobs:
  update-gradle-wrapper:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - name: Update Gradle Wrapper
        uses: gradle-update/update-gradle-wrapper-action@v1
        with:
          reviewers: |
            ChrisCarini
EOF

  git add .github/workflows/update-gradle-wrapper.yml

  ##
  # Commit the changes, and create the PR
  ##
  git commit -m 'Adding @ChrisCarini to reviewers for "Update Gradle Wrapper" GitHub Action.'
  git push -u origin "${GITHUB_BRANCH}"

  gh pr create \
    --base "${MAIN_BRANCH}" \
    --title 'Adding @ChrisCarini to reviewers for "Update Gradle Wrapper" GitHub Action.' \
    --body 'Adding @ChrisCarini to reviewers for "Update Gradle Wrapper" GitHub Action.' \
    --head "${GITHUB_BRANCH}" \
    --reviewer ChrisCarini
  git checkout "${MAIN_BRANCH}"

  popd

  echo "--------------------------------------------"
  echo # Give some breathing room between outputs..
done

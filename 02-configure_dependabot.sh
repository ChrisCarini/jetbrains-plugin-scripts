#!/bin/bash
###########################################################################
# Instructions:
#   1) `cd` into the directory containing JetBrains plugins (ie, `~/GitHub/jetbrains/plugins`)
#   2) Run: ../jetbrains-plugin-scripts/02-configure_dependabot.sh
###########################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
GITHUB_USERNAME=ChrisCarini

for d in */; do
    echo "============================================"
    echo "Processing ${d}"

    pushd "${d}"

    ##
    # Create the branch we will use
    ##
    GITHUB_BRANCH="${GITHUB_USERNAME}/updateDependabotConfiguration"
    git checkout master && git pull
    git checkout -b "${GITHUB_BRANCH}"

    ##
    # Install Automerge & Freshness guardian (https://go/github/docs/ci-settings)
    ##
    mkdir -p .github/ && touch .github/dependabot.yml

    cat <<"EOF" | perl -pe 'chomp if eof' >.github/dependabot.yml
# Dependabot configuration:
# https://docs.github.com/en/free-pro-team@latest/github/administering-a-repository/configuration-options-for-dependency-updates

version: 2
updates:
  # Maintain dependencies for Gradle dependencies
  - package-ecosystem: "gradle"
    directory: "/"
    schedule:
      interval: "daily"

  # Maintain dependencies for GitHub Actions
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "daily"
    labels:
      - "merge when passing"  # This is a label that [Repo Ranger](https://github.com/apps/repo-ranger) will pickup and auto-merge when all GH checks pass.
EOF

    git add .github/dependabot.yml

    ##
    # Commit the changes, and create the PR
    ##
    git commit -m 'Removing newline-removal.'
    git push -u origin "${GITHUB_BRANCH}"

    popd

    echo "--------------------------------------------"
    echo # Give some breathing room between outputs..
done

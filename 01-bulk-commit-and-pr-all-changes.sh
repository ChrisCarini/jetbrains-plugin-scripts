#!/bin/bash
###########################################################################
# Instructions:
#   1) `cd` into the directory containing JetBrains plugins (ie, `~/GitHub/jetbrains/plugins`)
#   2) Run: ../jetbrains-plugin-scripts/01-bulk-commit-and-pr-all-changes.sh
###########################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
GITHUB_USERNAME=ChrisCarini

for d in */; do
    echo "==========================="
    echo "Processing ${d}"

    pushd "${d}"

    ##
    # Create the branch we will use
    ##
    git checkout master
    GITHUB_BRANCH="${GITHUB_USERNAME}/fixIJProblems"
    git checkout -b "${GITHUB_BRANCH}"

    ##
    # Add all changed files
    ##
    git add ./

    ##
    # Commit the changes, and create the PR
    ##
    git commit -m "Fixing a few problems identified by IntelliJ."
    git push -u origin "${GITHUB_BRANCH}"

    ##
    # Go back to the main branch
    ##
    git checkout master

    popd

    echo
    echo # Give some breathing room between outputs..
done

#!/bin/bash
###########################################################################
# Instructions:
#   1) `cd` into the directory containing JetBrains plugins (ie, `~/GitHub/jetbrains/plugins`)
#   2) Run: ../jetbrains-plugin-scripts/00-TEMPLATE_configure_X.sh
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
    GITHUB_BRANCH="${GITHUB_USERNAME}/DESCRIPTION_OF_WHAT_YOU_ARE_DOING"
    git checkout master && git pull
    git checkout -b "${GITHUB_BRANCH}"

    ##
    # <DO_THE_THING_YOU_WANT_TO_DO>
    ##


    ##
    # Add all changed files
    ##
    git add ./

    ##
    # Commit the changes, and create the PR
    ##
    git commit -m "<DESCRIPTION_OF_WHAT_YOU_ARE_DOING_FOR_GIT_COMMIT>"
    git push -u origin "${GITHUB_BRANCH}"

    ##
    # Go back to the main branch
    ##
    git checkout master

    popd

    echo
    echo # Give some breathing room between outputs..
done

#!/bin/bash
###########################################################################
# Instructions:
#   1) `cd` into the directory containing JetBrains plugins (ie, `~/GitHub/jetbrains/plugins`)
#   2) Run: ../jetbrains-plugin-scripts/00-git-checkout-default-branch.sh
###########################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

for d in */; do
  echo "============================================"
  echo "Processing ${d}"

  pushd "${d}"

  ##
  # Create the branch we will use
  ##
  MAIN_BRANCH="$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')"
  git checkout "${MAIN_BRANCH}"

  popd

  echo "--------------------------------------------"
  echo # Give some breathing room between outputs..
done
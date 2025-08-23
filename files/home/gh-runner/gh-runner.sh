#! /bin/bash
set -Eeuo pipefail
gh auth login --with-token < "${GH_TOKEN_FILE}" \
&& GH_RUNNER_TOKEN=$(gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -q ".token" \
    "/repos/${GH_OWNER}/${GH_REPO}/actions/runners/registration-token") \
&& ./config.sh \
        --unattended \
        --replace \
        --disableupdate \
        --ephemeral \
        --url "${GH_SCHEMA}://${GH_HOST}/${GH_OWNER}/${GH_REPO}" \
        --token "${GH_RUNNER_TOKEN}" \
        --labels "${GH_RUNNER_LABELS}" \
&& ./run.sh

./gh-runner-remove.sh
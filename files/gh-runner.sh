#! /bin/bash
./config.sh \
    --unattended \
    --replace \
    --disableupdate \
    --ephemeral \
    --url "${GITHUB_URL}" \
    --token "${GITHUB_TOKEN}" \
    --labels "${GITHUB_LABELS}" \
&& GITHUB_TOKEN="" ./run.sh \
&& ./config.sh remove --token "${GITHUB_TOKEN}"
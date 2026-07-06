#!/usr/bin/env bash
# Executed on the EC2 instance by the Jenkins "deploy" stage.
# $1 = full image repo (e.g. <registry>/<repo>), $2 = image tag
set -euo pipefail

export DOCKERHUB_REPO="$1"
export TAG="$2"

docker-compose -f docker-compose.yaml up --detach
echo "success"

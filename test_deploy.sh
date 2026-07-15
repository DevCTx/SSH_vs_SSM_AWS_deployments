#!/bin/bash
#
# Triggers a real pipeline run (empty commit + push), then verifies:
#   1. Docker Hub only contains the latest image tag
#   2. The container running on EC2 matches that latest tag
#
set -e
cd "$(dirname "$0")"

[ -f .env ] && { set -a; source .env; set +a; }
: "${DOCKER_USERNAME:?Set DOCKER_USERNAME in .env}"
: "${DOCKERHUB_PAT:?Set DOCKERHUB_PAT in .env}"
: "${EC2_IP:?Set EC2_IP in .env}"

unset GITHUB_TOKEN   # avoid interfering with git push auth (gh/credential helper)

IMAGE_NAME="demo-java-app"
CONTAINER_NAME="java-app"
SSH_KEY="aws_ssh_ec2_install/jenkins-ec2.pem"
MAX_WAIT=300   # seconds to wait for the pipeline to finish

command -v jq >/dev/null || { echo "Install jq: sudo apt install -y jq"; exit 1; }

get_tags() {
  curl -sf "https://hub.docker.com/v2/repositories/$DOCKER_USERNAME/$IMAGE_NAME/tags?page_size=100" \
    | jq -r '.results[].name'
}

####################################################################################################
# 1. Record the tag(s) present BEFORE the push, then trigger the pipeline
####################################################################################################

TAGS_BEFORE=$(get_tags)
echo "Tags before push: $TAGS_BEFORE"

echo ""
echo "=== Triggering pipeline via push ==="
git commit --allow-empty -m "test webhook" && git push

####################################################################################################
# 2. Wait for a genuinely NEW tag to appear (build+push stage done)
####################################################################################################

echo ""
echo "=== Waiting for a new image tag to be pushed (max ${MAX_WAIT}s) ==="
ELAPSED=0
NEW_TAG=""
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  TAGS=$(get_tags)
  NEW_TAG=$(comm -13 <(echo "$TAGS_BEFORE" | sort) <(echo "$TAGS" | sort) | head -1)
  [ -n "$NEW_TAG" ] && break
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [ -z "$NEW_TAG" ]; then
  echo "❌ No new tag appeared within ${MAX_WAIT}s — build may have failed"
  exit 1
fi
echo "New tag detected: $NEW_TAG"

####################################################################################################
# 3. Wait for cleanup: only that new tag should remain (pipeline fully finished)
####################################################################################################

echo ""
echo "=== Waiting for Docker Hub cleanup to finish (max ${MAX_WAIT}s) ==="
ELAPSED=0
LATEST_TAG="$NEW_TAG"
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  TAGS=$(get_tags)
  COUNT=$(echo "$TAGS" | grep -c .)
  if [ "$COUNT" -eq 1 ] && [ "$(echo "$TAGS")" = "$NEW_TAG" ]; then
    break
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

echo ""
echo "Tags currently on Docker Hub:"
echo "$TAGS"

if [ "$(echo "$TAGS" | grep -c .)" -eq 1 ] && [ "$TAGS" = "$NEW_TAG" ]; then
  echo "✅ Docker Hub contains only the latest tag: $LATEST_TAG"
else
  echo "❌ Docker Hub cleanup incomplete — still multiple tags after ${MAX_WAIT}s"
fi

####################################################################################################
# 3. Check the tag actually running on EC2
####################################################################################################

echo ""
echo "=== Checking running image tag on EC2 ==="
RUNNING_IMAGE=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "ec2-user@$EC2_IP" \
  "docker inspect --format='{{.Config.Image}}' $CONTAINER_NAME" 2>/dev/null || echo "unreachable")

echo "Running on EC2: $RUNNING_IMAGE"
echo "Expected:       $DOCKER_USERNAME/$IMAGE_NAME:$LATEST_TAG"

if [ "$RUNNING_IMAGE" = "$DOCKER_USERNAME/$IMAGE_NAME:$LATEST_TAG" ]; then
  echo "✅ EC2 is running the latest version ($LATEST_TAG)"
else
  echo "❌ EC2 is NOT running the latest version"
  exit 1
fi

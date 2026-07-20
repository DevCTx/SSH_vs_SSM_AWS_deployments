#!/bin/bash
#
# Triggers a CI/CD pipeline run then verifies
# - Load the env: DOCKER_USERNAME, DOCKERHUB_PAT, EC2_IP from .env;
# - Get the last name of the image on DockerHub before the push
# - Trigger the pipeline with an empty commit and git push
# - Wait for the build on Jenkiins and new tag on Docker Hub
# - Wait for cleanup on Docker Hub
# - Verify EC2: connect via SSH and check if the image tag running the container is the last created
#
set -e
cd "$(dirname "$0")"

# Load the env
[ -f .env ] && { set -a; source .env; set +a; }
: "${JENKINS_IP:?Set JENKINS_IP in .env first}"
: "${DOCKER_USERNAME:?Set DOCKER_USERNAME in .env first}"
: "${DOCKERHUB_PAT:?Set DOCKERHUB_PAT in .env first}"
: "${SSH_EC2_IP:?Set SSH_EC2_IP in .env first}"

command -v jq >/dev/null || { echo "Please Install jq first (sudo apt install -y jq)"; exit 1; }


# Get the last name on Docker Hub
LAST_BUILD_BEFORE=$(curl -s -u "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" \
  "http://$JENKINS_IP:8080/job/ssh-dockerhub-ec2/lastBuild/buildNumber" 2>/dev/null || echo 0)

echo ""
echo "=== Trigger the pipeline with an empty commit and git push ==="
git commit --allow-empty -m "test webhook" && git push


echo ""
echo ""
echo "=== Follow the steps on Jenkins ==="
echo "Open http://$JENKINS_IP:8080/job/ssh-dockerhub-ec2/"
echo "Please wait the steps result until 5 minutes ..."
echo ""

ELAPSED=0
JENKINS_RESULT=""
while [ "$ELAPSED" -lt "300" ]; do
  CURRENT_BUILD=$(curl -s -u "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" \
      "http://$JENKINS_IP:8080/job/ssh-dockerhub-ec2/lastBuild/buildNumber" 2>/dev/null || echo 0)
  if [ "$CURRENT_BUILD" -gt "$LAST_BUILD_BEFORE" ]; then
    JENKINS_RESULT=$(curl -s -u "$JENKINS_ADMIN_USER:$JENKINS_ADMIN_PASSWORD" \
    "http://$JENKINS_IP:8080/job/ssh-dockerhub-ec2/$CURRENT_BUILD/api/json" | jq -r '.result')
    [ "$JENKINS_RESULT" = "SUCCESS" ] && break
    [ "$JENKINS_RESULT" = "FAILURE" ] && break
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

if [ -z "$JENKINS_RESULT" ] || [ "$JENKINS_RESULT" = "null" ]; then
  echo "Jenkins pipeline result: Timeout !"
  exit 1
elif [ "$JENKINS_RESULT" != "SUCCESS" ]; then
  echo "Jenkins pipeline result: $JENKINS_RESULT"
  exit 1
fi

echo ""
echo "Jenkins pipeline result: ${JENKINS_RESULT}"
echo "You should see all green on steps"
echo ""
echo ""
echo "=== Check result on Docker Hub ==="
echo "Open https://hub.docker.com/repository/docker/$DOCKER_USERNAME/demo-java-app/general"
echo ""
DOCKERHUB_RESULT=$(curl -sf "https://hub.docker.com/v2/repositories/$DOCKER_USERNAME/demo-java-app/tags?page_size=100" | jq -r '.results[].name')
echo "Docker Hub image tag : $DOCKERHUB_RESULT"
echo "You should see only one image"

echo ""
echo ""
echo "=== Check result on EC2 ==="
EC2_RESULT=$(ssh -o StrictHostKeyChecking=no -i "aws_ec2_install/ssh-ec2-key.pem" ec2-user@$SSH_EC2_IP \
  "docker inspect --format='{{.Config.Image}}' java-app")
echo ""
echo "EC2 container image tag : $EC2_RESULT"
echo "You should see only one image"
echo ""
echo "To inspect manually: ssh -i aws_ec2_install/ssh-ec2-key.pem ec2-user@$SSH_EC2_IP \"docker ps\" "
echo ""
echo ""
echo "=== Check the Java App ==="
echo ""
echo "Open http://$SSH_EC2_IP:3080"
echo "You should see a message from the Java App"
echo ""

#!/bin/bash
#
# Cleanly removes everything created by docker_jenkins_platform_install.sh
# (controller + agent images, container, volume, generated files).
# Docker itself is NOT removed unless you confirm.
#
set -e
cd "$(dirname "$0")"

COMPOSE_DIR="./jenkins"

echo "=== Stop & remove the Jenkins stack ==="
if [ -f "$COMPOSE_DIR/docker-compose.yaml" ]; then
  # down -v also removes the jenkins_home named volume
  (cd "$COMPOSE_DIR" && docker compose down -v 2>/dev/null) || true
else
  # fallback if the compose file is gone
  docker rm -f jenkins 2>/dev/null || true
  docker volume rm jenkins_jenkins_home jenkins_home 2>/dev/null || true
fi

echo "=== Remove leftover agent containers (before their images) ==="
for img in jenkins-maven-agent jenkins-aws-agent jenkins-docker-agent jenkins/inbound-agent; do
  docker ps -aq --filter "ancestor=$img" | xargs -r docker rm -f 2>/dev/null || true
done

echo "=== Remove built images ==="
for img in jenkins-controller jenkins-docker-agent jenkins-maven-agent jenkins-aws-agent; do
  docker rmi -f "$img" 2>/dev/null && echo "  removed $img" || true
done

echo "=== Remove generated files (./jenkins tree) ==="
rm -rf "$COMPOSE_DIR"
echo "  ./jenkins removed"

echo ""
echo "=== Stop Cloudflare tunnel (if running) ==="
CF_PID=$(pgrep -f "cloudflared tunnel" || true)
if [ -n "$CF_PID" ]; then
  kill "$CF_PID"
  echo "  cloudflared (PID $CF_PID) stopped"
else
  echo "  no cloudflared tunnel running"
fi

echo ""
echo "=== Clean Jenkins-specific vars from .env ==="
if [ -f "$ENV_FILE" ]; then
  grep -vE "^(JENKINS_ADMIN_USER|JENKINS_ADMIN_PASSWORD)=" "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
fi

echo ""
echo "✅ Jenkins platform uninstalled."

# --- Optional: remove Docker Engine from the host ---
read -p "Also uninstall Docker Engine from the host? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  sudo systemctl disable --now docker 2>/dev/null || true
  sudo apt-get purge -y docker-ce docker-ce-cli containerd.io \
       docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
  sudo rm -rf /var/lib/docker /var/lib/containerd
  sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
  echo "Docker Engine removed."
else
  echo "Docker Engine kept."
fi

echo "=== Remove leftover temp files ==="
rm -f cf.log .env.tmp

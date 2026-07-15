#!/bin/bash

set -e
cd "$(dirname "$0")"    # Runs the script into this folder


####################################################################################################
# 1. Set the Environment Variables
# Source .env : GITHUB_OWNER, GITHUB_TOKEN, REPO
####################################################################################################

[ -f ../.env ] && { set -a; source ../.env; set +a; }
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN in .env}"
: "${REPO:?Set REPO=<owner>/<repo> in .env}"
 
API="https://api.github.com/repos/$REPO/hooks"
AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json")


####################################################################################################
# 2. Asks if Jenkins has a Public IP, or mount a Cloudflare tunnel
# Cloudflare tunnel is an ephemeral URL if used without account and 
# will change on each launch, that's why this script update the webhook.
####################################################################################################

command -v curl >/dev/null || { echo "Install curl: sudo apt install -y curl"; exit 1; }
 
read -p "Is Jenkins on a public IP reachable from GitHub? [y/N] " public
if [[ "$public" =~ ^[Yy]$ ]]; then
  echo ""
  echo "Use of the local Jenkins Public IP address"
  # display the Jenkins public IP
  IP=$(curl -sf -4 ifconfig.me) || { echo "Could not fetch public IP"; exit 1; }
  BASE="http://${IP}:8080"   
else
  echo ""
  echo "Creation of a public tunnel with Cloudflared"
  # Tests if cloudflared is available or install it then creates a tunnel to public IP
  command -v cloudflared >/dev/null || {
    echo "Install: curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb && sudo dpkg -i cloudflared.deb"
    exit 1
  }
  cloudflared tunnel --url "http://$(hostname -I | awk '{print $1}'):8080" > cf.log 2>&1 &
  CF_PID=$!
  sleep 8
  BASE=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' cf.log | head -1)
  [ -n "$BASE" ] || { echo "Tunnel failed to start — see cf.log"; kill "$CF_PID" 2>/dev/null; exit 1; }
  echo "Jenkins available on : $BASE"
  echo ""
  echo "To stop it: kill $CF_PID"
  echo "Tunnel URL changes on restart, so re-run this script to update the webhook if you kill it"
fi
HOOK_URL="$BASE/github-webhook/"


####################################################################################################
# 3. Find the hook (by /jenkins-webhook/), create if absent, else update -> idempotent
####################################################################################################

github_api() {
  local method="$1" url="$2" body="${3:-}"
  local resp code
  # -w writes the status code on the last line; -o keeps the JSON body
  if [ -n "$body" ]; then
    resp=$(curl -s -w $'\n%{http_code}' -X "$method" "${AUTH[@]}" "$url" -d "$body")
  else
    resp=$(curl -s -w $'\n%{http_code}' -X "$method" "${AUTH[@]}" "$url")
  fi
  code=$(printf '%s' "$resp" | tail -n1)
  body=$(printf '%s' "$resp" | sed '$d')
 
  case "$code" in
    2*) printf '%s' "$body"; return 0 ;;
    401) echo "ERROR 401 — bad or expired GITHUB_TOKEN. Check the token in .env." >&2 ;;
    403) echo "ERROR 403 — the token lacks the webhook permission." >&2
         echo "  Fine-grained token: Repository permissions > Webhooks > Read and write." >&2
         echo "  Classic token:      scope 'admin:repo_hook' (or full 'repo')." >&2 ;;
    404) echo "ERROR 404 — repo '$REPO' not found, or the token can't see it." >&2
         echo "  Check REPO=<owner>/<repo> in .env and the token's repository access." >&2 ;;
    *)   echo "ERROR $code — unexpected GitHub API response:" >&2 ;;
  esac
  echo "  GitHub says: $(printf '%s' "$body" | jq -r '.message // .' 2>/dev/null)" >&2
  exit 1
}

command -v jq >/dev/null || { echo "Install jq: sudo apt install -y jq"; exit 1; }

HOOK_ID=$(github_api GET "$API" \
  | jq -r '.[] | select(.config.url | test("github-webhook")) | .id' | head -1)
 
BODY=$(jq -n --arg url "$HOOK_URL" \
  '{name:"web", config:{url:$url, content_type:"json"}, events:["push"], active:true}')
 
if [ -n "$HOOK_ID" ]; then
  github_api PATCH "$API/$HOOK_ID" "$BODY" >/dev/null
  echo ""
  echo "✅ Webhook UPDATED (id $HOOK_ID) -> $HOOK_URL"
else
  github_api POST "$API" "$BODY" >/dev/null
  echo ""
  echo "✅ Webhook CREATED -> $HOOK_URL"
fi

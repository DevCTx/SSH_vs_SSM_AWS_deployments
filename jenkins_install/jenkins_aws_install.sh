#!/bin/bash
# 
# jenkins_aws_install.sh 
# - transfers jenkins install/, the SSH key, and .env to the $Jenkins_EC2_IP 
# - executes jenkins_local_install.sh remotely on that instance 
#
set -e
cd "$(dirname "$0")"    # jenkins_install/

ENV_FILE="$(pwd)/../.env"
set -a; source "$ENV_FILE"; set +a   # get the .env variables (JENKINS_EC2_IP, ...)

JENKINS_KEY="../aws_ec2_install/jenkins-ec2-key.pem"  # to send the file via SSH
SSH_EC2_KEY="../aws_ec2_install/ssh-ec2-key.pem"      # to let Jenkins connect to SSH_EC2-instance
REMOTE_HOME="/home/ec2-user"                          # Work folder

echo ""
echo "=== Preparing remote folders ==="
ssh -i "$JENKINS_KEY" "ec2-user@$JENKINS_EC2_IP" \
  "mkdir -p $REMOTE_HOME/aws_ec2_install"

ssh -i "$JENKINS_KEY" "ec2-user@$JENKINS_EC2_IP" \
  "mkdir -p $REMOTE_HOME/jenkins_install"

echo ""
echo "=== Transferring SSH key + .env ==="
scp -i "$JENKINS_KEY" "$SSH_EC2_KEY" \
  "ec2-user@$JENKINS_EC2_IP:$REMOTE_HOME/aws_ec2_install/"

scp -i "$JENKINS_KEY" "$ENV_FILE" \
  "ec2-user@$JENKINS_EC2_IP:$REMOTE_HOME/"

echo ""
echo "=== Transferring jenkins install and uninstall files ==="
scp -i "$JENKINS_KEY" jenkins_local_install.sh jenkins_local_uninstall.sh setup_github_webhook.sh\
  "ec2-user@$JENKINS_EC2_IP:$REMOTE_HOME/jenkins_install/"

echo ""
echo "=== Running jenkins_local_install.sh remotely ==="
ssh -t -i "$JENKINS_KEY" "ec2-user@$JENKINS_EC2_IP" \
  "sudo $REMOTE_HOME/jenkins_install/jenkins_local_install.sh"

echo ""
echo "=== Running setup_github_webhook.sh remotely to set the webhook ==="
ssh -t -i "$JENKINS_KEY" "ec2-user@$JENKINS_EC2_IP" \
  "sudo $REMOTE_HOME/jenkins_install/setup_github_webhook.sh"

echo ""
echo "=== Retrieving Jenkins credentials from remote .env ==="
scp -i "$JENKINS_KEY" "ec2-user@$JENKINS_EC2_IP:$REMOTE_HOME/.env" /tmp/remote.env

for var in JENKINS_ADMIN_USER JENKINS_ADMIN_PASSWORD JENKINS_IP; do
  value=$(grep "^$var=" /tmp/remote.env | cut -d= -f2-)
  grep -v "^$var=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
  echo "$var=$value" >> "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
done

rm -f /tmp/remote.env
echo "Jenkins credentials merged into local .env"
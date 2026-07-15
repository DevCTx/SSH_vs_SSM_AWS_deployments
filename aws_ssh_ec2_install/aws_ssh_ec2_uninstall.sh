#!/bin/bash
set -e
cd "$(dirname "$0")"

JENKINS_KEY=jenkins-ec2
SG=jenkins-sg
REGION=eu-west-3
NAME_SSH=MyApp-SSH

# 1. Terminate the instance(s) tagged myApp-instance
echo "Looking for ${NAME_SSH}-instance ..."
IIDS=$(aws ec2 describe-instances --region $REGION \
  --filters "Name=tag:Name,Values=${NAME_SSH}-instance" \
            "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

if [ -n "$IIDS" ]; then
  echo "Terminating: $IIDS"
  aws ec2 terminate-instances --instance-ids $IIDS --region $REGION >/dev/null
  aws ec2 wait instance-terminated --instance-ids $IIDS --region $REGION
  echo "Instances terminated."
else
  echo "No instance found."
fi

# 2. Delete the security group (must wait until no instance uses it)
echo "Deleting security group $SG ..."
aws ec2 delete-security-group --group-name $SG --region $REGION 2>/dev/null \
  && echo "Security group deleted." \
  || echo "Security group absent or still in use."

# 3. Delete the key pair (AWS side) + local .pem
echo "Deleting key pair $JENKINS_KEY ..."
aws ec2 delete-key-pair --key-name $JENKINS_KEY --region $REGION 2>/dev/null \
  && echo "Key pair deleted on AWS." || echo "Key pair absent on AWS."
rm -f "$JENKINS_KEY.pem" && echo "Local $JENKINS_KEY.pem removed."

echo ""
echo "Teardown complete. You can re-run aws_ssh_ec2_install.sh from scratch."
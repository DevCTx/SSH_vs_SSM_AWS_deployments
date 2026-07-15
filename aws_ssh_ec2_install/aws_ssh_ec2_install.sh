
#!/bin/bash
set -e
cd "$(dirname "$0")"    # Runs the script into this folder

JENKINS_KEY=jenkins-ec2     # SSH KEY for connecting jenkins to EC2 
SG=jenkins-sg       # Security group for EC2 Instance 
REGION=eu-west-3    # Paris
NAME_SSH=MyApp-SSH

MY_IPV4=$(curl -s -4 ifconfig.me)


#############################################################################
# Configuration for SSH-EC2-instance ()
#############################################################################

# 1. Create a SSH Key to let Jenkins connect to the EC2
echo ""
echo "Test if Key pair exists for Jenkins on local else (re)create it"
if [ ! -f "$JENKINS_KEY.pem" ]; then
  aws ec2 delete-key-pair --key-name "$JENKINS_KEY" --region "$REGION" 2>/dev/null || true
  aws ec2 create-key-pair --key-name "$JENKINS_KEY" --region "$REGION" \
    --query 'KeyMaterial' --output text > "$JENKINS_KEY.pem"
fi
chmod 400 "$JENKINS_KEY.pem"      # required by AWS

# 2. Security group + rules for ports TCP 22 and 3080
echo ""
echo "Test if Security Group exists or create it with TCP 22 and 3080 opened"
SG_ID=$(aws ec2 describe-security-groups --group-names $SG --region $REGION \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null) || \
SG_ID=$(aws ec2 create-security-group --group-name $SG \
  --description "${JENKINS_KEY}" --region $REGION --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 22   --cidr $MY_IPV4/32 --region $REGION 2>/dev/null || true

aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 3080 --cidr 0.0.0.0/0 --region $REGION 2>/dev/null || true

# 3. AWS Linux 2023 Instance with a preinstalled Docker (user-data)

# Get the AMI dynamically because it changes with time and region
AL2023_AMI=$(aws ec2 describe-images --region $REGION --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)

echo ""
echo "Tests if EC2 exists or Create it and install docker"

# Mount an instance t3.micro (2 vCPU, 1 Gio de RAM) with AWS Linux 2023
# then install Docker and active the daemon on start
IID=$(aws ec2 describe-instances --region $REGION \
  --filters "Name=tag:Name,Values=${NAME_SSH}-instance" \
            "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text 2>/dev/null)

if [ "$IID" = "None" ] || [ -z "$IID" ]; then
  echo "Creating ${NAME_SSH}-instance..."

  # Install Docker and active the daemon on start
  cat > /tmp/user-data.sh <<'EOF'
#!/bin/bash
yum update -y
yum install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user
EOF

  IID=$(aws ec2 run-instances --region $REGION \
    --image-id $AL2023_AMI \
    --count 1 \
    --instance-type t3.micro \
    --key-name $JENKINS_KEY \
    --security-group-ids $SG_ID \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME_SSH}-instance}]" \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":16,"VolumeType":"gp3"}}]' \
    --query 'Instances[0].InstanceId' \
    --output text \
    --user-data file:///tmp/user-data.sh)  # file:// + /tmp/...
else
  echo "Instance already exists: $IID"
fi

echo ""
echo "Waiting for $IID to be running..."
aws ec2 wait instance-running --instance-ids "$IID" --region $REGION

# Get the public IP address reachable
echo ""
IP=$(aws ec2 describe-instances --region $REGION --instance-ids "$IID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

ENV_FILE="../.env"

# update or insert the keys into .env
set_env() {
  grep -v "^$1=" "$ENV_FILE" 2>/dev/null > "$ENV_FILE.tmp" || true
  echo "$1=$2" >> "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
}

set_env EC2_IP "$IP"

echo ""
echo "Public IP address of ${NAME_SSH} EC2 : ${IP}   (updated into .env)"
echo "and SSH KEY created into $(dirname "$0")/$JENKINS_KEY.pem "
echo ""


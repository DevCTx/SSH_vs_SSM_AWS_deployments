
#!/bin/bash
#
# aws_shared_library.sh : Shared library for AWS functions (SSH & SSM deployments)
# Use it through another script : source ./aws_shared_library.sh
#


# AWS REGION predefined
REGION=eu-west-3            # Paris

# Get Local IP V4
MY_IPV4=$(curl -s -4 ifconfig.me)

ENV_FILE="../.env"
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }


####################################################
# Get and prepare the AMI + volume size
####################################################
init_ami_info() {

  echo "" >&2
  echo "Get and prepare the AMI + volume size" >&2

  # Get information about the AMI because it changes with time and region (ami id)
  AL2023_AMI=$(aws ec2 describe-images --region $REGION --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-x86_64" \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
 
  # Get the size required by AWS for this image
  IMAGE_SIZE=$(aws ec2 describe-images --region $REGION --image-ids $AL2023_AMI \
    --query 'Images[0].BlockDeviceMappings[0].Ebs.VolumeSize' --output text)
 
  # Ensure enough disk for the app: AMI's required minimum size + 10GB margin (our config)
  VOLUME_SIZE=$(($IMAGE_SIZE + 10))
}


############################################################
# Prepare the script to install Docker + Compose + Buildx 
# on EC2 instance (yum) on first start (via user-data arg)
############################################################
prepare_install_docker_script() {
  echo "" >&2
  echo "Prepare the script to install Docker + Compose + Buildx " >&2
  cat > /tmp/install-docker.sh <<'EOF'
#!/bin/bash
yum update -y
yum install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

# Install Docker Compose v2 and BuildX plugins (not included with yum's docker package)
mkdir -p /usr/local/lib/docker/cli-plugins

curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

BUILDX_VERSION="v0.35.0"
curl -SL "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64" \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
EOF
}


####################################################
# CHECK IF A SSH KEY EXISTS ON LOCAL OR CREATES IT
# use : create_SSH_key <key_name>
####################################################
create_SSH_key() {
  local key_name="$1"

  echo "" >&2
  echo "Test if Key pair exists for $key_name else (re)create it" >&2

  if [ ! -f "$key_name.pem" ]; then
    aws ec2 delete-key-pair --key-name "$key_name" --region "$REGION" >/dev/null 2>&1  || true
    aws ec2 create-key-pair --key-name "$key_name" --region "$REGION" \
      --query 'KeyMaterial' --output text > "$key_name.pem"
  fi
  
  chmod 400 "$key_name.pem"   # required by AWS
}


####################################################
# DELETE A KEY PAIR (AWS side) + LOCAL .pem
# use : delete_key <key_name>
####################################################
delete_SSH_key() {
  local key_name="$1"

  echo "" >&2
  echo "Deleting key pair $key_name ..." >&2
  
  aws ec2 delete-key-pair --key-name "$key_name" --region $REGION >/dev/null 2>&1  \
    && echo "Key pair deleted on AWS." >&2 || echo "Key pair absent on AWS." >&2
  
  rm -f "$key_name.pem" && echo "Local $key_name.pem removed."
}


################################################################################
# PREPARE SSM ROLE AND PROFILE FOR INSTANCE
# use : prepare_SSM_role_and_profile <role_name> <profile_name>
################################################################################
prepare_SSM_role_and_profile() {
  local role_name="$1"
  local profile_name="$2"

  echo "" >&2
  echo "Create a SSM Role ($role_name) and Profile ($profile_name) for an EC2 instance" >&2

  # The SSM agent is already installed on Amazon Linux 2023 
  # But the instance needs an IAM Role with a SSM policy to use it
  # because only users, groups or roles can have IAM permissions

  cat > /tmp/ec2-assume-role-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

  # Create a role that can be accepted by the EC2 AWS Manager -> Role understanding by EC2
  aws iam get-role --role-name "$role_name" >/dev/null 2>&1 || \
    aws iam create-role --role-name "$role_name" \
      --assume-role-policy-document file:///tmp/ec2-assume-role-policy.json >/dev/null 2>&1 

  # Attach a policy (SSM permissions) to this role -> SSM Role understanding by EC2
  aws iam list-attached-role-policies --role-name "$role_name" \
    --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore']" \
    --output text | grep -q . || \
    aws iam attach-role-policy --role-name "$role_name" \
      --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore >/dev/null 2>&1 

  # Create an instance profile to be able to set a role to an specific instance -> EC2 Instance Profile
  aws iam get-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1 || \
    aws iam create-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1 

  # Attach the SSM role to the Instance Profile -> Acceptable SSM Role for EC2 Instance
  aws iam add-role-to-instance-profile \
    --instance-profile-name "$profile_name" --role-name "$role_name" >/dev/null 2>&1  || true

  sleep 10   # let IAM propagate the instance profile
}


####################################################
# DELETE AN IAM INSTANCE PROFILE + ROLE (SSM)
# use : delete_ssm_role_and_profile <role_name> <profile_name>
####################################################
delete_SSM_role_and_profile() {
  local role_name="$1"
  local profile_name="$2"

  echo "" >&2
  echo "Delete SSM Role ($role_name) and Profile ($profile_name)" >&2

  # Detach the role from the instance profile first (required before deletion)
  aws iam remove-role-from-instance-profile \
    --instance-profile-name "$profile_name" --role-name "$role_name" >/dev/null 2>&1  || true

  aws iam delete-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1  \
    && echo "Instance profile deleted." >&2 || echo "Instance profile absent." >&2

  aws iam detach-role-policy --role-name "$role_name" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore >/dev/null 2>&1  || true

  aws iam delete-role --role-name "$role_name" >/dev/null 2>&1  \
    && echo "Role deleted." >&2 || echo "Role absent." >&2

  rm -f "/tmp/ec2-assume-role-policy.json"
}



####################################################
# CHECK IF A SECURITY GROUP EXISTS OR CREATE IT
# use : SG=$(create_sg <sg_name>)
####################################################
create_sg() {
  local sg_name="$1"

  echo "" >&2
  echo "Test if $sg_name Security Group exists or create it" >&2

  aws ec2 describe-security-groups --group-names "$sg_name" --region $REGION \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || \
  aws ec2 create-security-group --group-name "$sg_name" \
    --description "$sg_name" --region $REGION --query 'GroupId' --output text
}
 

####################################################
# DELETE A SECURITY GROUP
# use : delete_sg <sg_name>
####################################################
delete_sg() {
  local sg_name="$1"

  echo "" >&2
  echo "Deleting security group $sg_name" >&2

  aws ec2 delete-security-group --group-name "$sg_name" \
    --region $REGION >/dev/null 2>/dev/null \
    && echo "Security group deleted." >&2 \
    || echo "Security group absent or still in use." >&2
}


##################################################################
# AUTHORIZE INGRESS ON <PORT> FROM <CIDR> IN <SECURITY GROUP>
# use : open_port <sg_id> <port> <cidr>
# if error : answers true
##################################################################
open_ingress_port() {
  local sg_id="$1" 
  local port="$2" 
  local cidr="$3"       

  echo "" >&2
  echo "Authorize ingress on port $port from cidr $cidr in security group $sg_id" >&2

  aws ec2 authorize-security-group-ingress --group-id "$sg_id" \
    --protocol tcp --port "$port" --cidr "$cidr" \
    --region $REGION >/dev/null 2>&1  || true
}


################################################################################
# CREATE INSTANCE WITH SSH ACCESS OR SSM INSTANCE PROFILE
# use : IID=$(create_instance <name> <sg_id> <instance_type> [ssh_key_name] [ssm_iam_profile])
################################################################################
create_instance() {
  local instance_type="$1"
  local i_name="$2" 
  local sg_id="$3" 
  local ssh_key_name="${4:-}"       # get or blank
  local ssm_iam_profile="${5:-}"    # get or blank 
 
  # Only Free Tier eligible - t3.small minimum required for Jenkins
  if [ "$instance_type" != "t3.micro" ] \
  && [ "$instance_type" != "t3.small" ] ; then
    echo "Invalid instance_type: '$instance_type' (allowed: t3.micro, t3.small)" >&2
  return 1
  fi

  echo "" >&2
  echo "Tests if the instance $i_name exists or creates it, install docker and wait for running" >&2
 
  # Check if the instance is already created
  local i_id=$(aws ec2 describe-instances --region $REGION \
    --filters "Name=tag:Name,Values=${i_name}-instance" \
              "Name=instance-state-name,Values=running,pending" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
 
  # if not ...
  if [ "$i_id" = "None" ] || [ -z "$i_id" ]; then
    echo "Creating AL2023_AMI ${i_name}-instance (${instance_type} with $VOLUME_SIZE GiB)..." >&2
    
    # define if the instance is based on SSH or SSM protocol
    # needs "${extra_args[@]}" because it returns [different elements]
    local protocol_args=()
    [ -n "$ssh_key_name" ] && protocol_args=(--key-name "$ssh_key_name")
    [ -n "$ssm_iam_profile" ] && protocol_args=(--iam-instance-profile "Name=$ssm_iam_profile")
 
    if [ -n "$ssh_key_name" ]; then
      echo "Protocol used : SSH (key: $ssh_key_name)" >&2
    elif [ -n "$ssm_iam_profile" ]; then
      echo "Protocol used : SSM (profile: $ssm_iam_profile)" >&2
    else
      echo "Protocol used : none (no key, no IAM profile provided)" >&2
    fi
 
    # Create the instance with these protocol arguments
    i_id=$(aws ec2 run-instances --region $REGION \
      --image-id "$AL2023_AMI" \
      --count 1 \
      --instance-type "$instance_type" \
      --security-group-ids "$sg_id" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${i_name}-instance}]" \
      --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":${VOLUME_SIZE},\"VolumeType\":\"gp3\"}}]" \
      "${protocol_args[@]}" \
      --query 'Instances[0].InstanceId' --output text \
      --user-data file:///tmp/install-docker.sh)  # file:// + /tmp/...
    echo "Instance created: $i_id" >&2
  else
    echo "Instance already exists: $i_id" >&2
  fi
 
  # Wait for the instance to run before to continue
  echo "Waiting for $i_name to be running..." >&2
  aws ec2 wait instance-running --instance-ids "$i_id" --region $REGION
  echo "$i_id"
}


####################################################
# TERMINATE A INSTANCE
# use : terminate_instance <name>
####################################################
terminate_instance() {
  local i_name="$1"

  echo "" >&2
  echo "Terminate $i_name-instance if exists" >&2

  local i_id=$(aws ec2 describe-instances --region $REGION \
    --filters "Name=tag:Name,Values=${i_name}-instance" \
              "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text)

  if [ -n "$i_id" ]; then
    aws ec2 terminate-instances --instance-ids $i_id --region $REGION >/dev/null
    echo "Waiting for completion ..." >&2
    aws ec2 wait instance-terminated --instance-ids $i_id --region $REGION
    echo "Instance terminated." >&2
  else
    echo "No instance found." >&2
  fi
}


################################################################################
# GET INSTANCE PUBLIC IP
# use : PUBLIC_IP=$(get_public_ip <instance_id>)
################################################################################
get_public_ip() {
  local instance_id="$1"

  echo "" >&2
  echo "Get the public IP address of $instance_id" >&2

  aws ec2 describe-instances --region $REGION --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
}


################################################################################
# UPDATE AN ENVIRONMENT VARIABLE
# use : set_env <env_var> <value>
################################################################################
set_env() {
  local env_var="$1"
  local value="$2"  

  echo "" >&2
  echo "Set $env_var at $value into it into $ENV_FILE file" >&2

  grep -v "^$env_var=" "$ENV_FILE" 2>/dev/null > "$ENV_FILE.tmp" || true
  echo "$env_var=$value" >> "$ENV_FILE.tmp"
  mv -f "$ENV_FILE.tmp" "$ENV_FILE"
}


####################################################
# REMOVE VARIABLES FROM .env
# use : unset_env <env_var>
####################################################
unset_env() {
  local env_var="$1"

  echo "" >&2
  echo "Unset $env_var from $ENV_FILE file" >&2

  [ -f "$ENV_FILE" ] || return 0
  grep -v "^$env_var=" "$ENV_FILE" > "$ENV_FILE.tmp" || true
  mv -f "$ENV_FILE.tmp" "$ENV_FILE"
}

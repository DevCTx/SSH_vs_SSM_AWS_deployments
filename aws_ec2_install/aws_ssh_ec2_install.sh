#!/bin/bash
#
# Create an EC2 instance for SSH deployment:
#   - SSH-EC2 : receives the web app via the ssh-dockerhub-ec2 pipeline
#
set -e
cd "$(dirname "$0")"    # Runs the script into this folder

source ./aws_shared_library.sh     # Use the AWS shared functions


# Get and prepare the AMI + volume size
init_ami_info

# Prepare the script to install Docker + Compose + Buildx 
prepare_install_docker_script


#############################################################################
# Configuration for SSH-EC2-instance for SSH Deployment
#############################################################################

SSH_EC2_NAME=ssh-ec2
SSH_EC2_KEY=ssh-ec2-key     # SSH KEY for connecting local jenkins to SSH-EC2 
SSH_EC2_SG=ssh-ec2-sg       # Security group for EC2 Instance 

# 1. Creates a SSH Key to let local Jenkins connect to the SSH-EC2
create_SSH_key $SSH_EC2_KEY

# 2. Security group + rules for ports TCP 22 and 3080
SSH_EC2_SG_ID=$(create_sg $SSH_EC2_SG)
open_ingress_port $SSH_EC2_SG_ID "22" "$JENKINS_IP/32"   # For local or remote Jenkins to connect
open_ingress_port $SSH_EC2_SG_ID "3080" "0.0.0.0/0"   # for anyone to web app

# 3. Creates an AWS Linux 2023 Instance and installs Docker (user-data)
SSH_EC2_ID=$(create_instance "t3.micro" $SSH_EC2_NAME $SSH_EC2_SG_ID $SSH_EC2_KEY)

# 4. Get the public IP address and set it into .env file
SSH_EC2_IP=$(get_public_ip "$SSH_EC2_ID")
set_env SSH_EC2_IP "$SSH_EC2_IP"

echo ""
echo "=================================================="
echo "  ${SSH_EC2_NAME} instance created"
echo "  Public IP : ${SSH_EC2_IP}   (saved as SSH_EC2_IP in ${ENV_FILE})"
echo "  SSH key : $(dirname "$0")/$SSH_EC2_KEY.pem"
echo "  Test access : ssh -i $(dirname "$0")/$SSH_EC2_KEY.pem ec2-user@${SSH_EC2_IP}"
echo "=================================================="
echo ""

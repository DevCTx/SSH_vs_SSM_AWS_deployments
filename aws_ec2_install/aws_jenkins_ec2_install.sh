#!/bin/bash
#
# Create 2 EC2 instances for SSM deployment:
#   - JENKINS-EC2 : receives the Jenkins app to run the pipeline via SSM
#   - SSM-EC2 : receives the web app via the ssm-ecr-ec2 pipeline
#
set -e
cd "$(dirname "$0")"    # Runs the script into this folder

source ./aws_shared_library.sh     # Use the AWS shared functions


# Get and prepare the AMI + volume size
init_ami_info

# Prepare the script to install Docker + Compose + Buildx 
prepare_install_docker_script


#############################################################################
# Configuration of Jenkins-instance for SSM Deployment
#############################################################################

JENKINS_EC2_NAME=jenkins-ec2
JENKINS_EC2_KEY=jenkins-ec2-key     # SSH KEY for connecting local to JENKINS-EC2
JENKINS_EC2_SG=jenkins-ec2-sg       # Security group for JENKINS-EC2 Instance 

# 1. Create a SSH Key to let local connect to the Jenkins-EC2
create_SSH_key $JENKINS_EC2_KEY

# 2. Security group + rules for ports TCP 22 and 8080 opened
JENKINS_EC2_SG_ID=$(create_sg $JENKINS_EC2_SG)
open_ingress_port $JENKINS_EC2_SG_ID "22" "$MY_IPV4/32"   # For local script to connect
open_ingress_port $JENKINS_EC2_SG_ID "8080" "0.0.0.0/0"   # For webhook on Jenkins

# 3. Creates an AWS Linux 2023 Instance and installs Docker (user-data)
JENKINS_EC2_ID=$(create_instance "t3.small" $JENKINS_EC2_NAME $JENKINS_EC2_SG_ID $JENKINS_EC2_KEY)

# 4. Get the public IP address and set it into .env file
JENKINS_EC2_IP=$(get_public_ip "$JENKINS_EC2_ID")
set_env JENKINS_EC2_IP "$JENKINS_EC2_IP"

echo ""
echo "=================================================="
echo "  ${JENKINS_EC2_NAME} instance created"
echo "  Public IP : ${JENKINS_EC2_IP}   (saved as JENKINS_EC2_IP in ${ENV_FILE})"
echo "  SSH key : $(dirname "$0")/$JENKINS_EC2_KEY.pem"
echo "  Test access : ssh -i $(dirname "$0")/$JENKINS_EC2_KEY.pem ec2-user@${JENKINS_EC2_IP}"
echo "=================================================="
echo ""

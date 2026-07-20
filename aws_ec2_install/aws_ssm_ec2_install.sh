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
# Configuration of SSM-EC2-instance for SSM Deployment
#############################################################################

SSM_EC2_ROLE=ssm-ec2-role         # Role for SSM permissions
SSM_EC2_PROFILE=ssm-ec2-profile   # Instance profile for EC2
SSM_EC2_SG=ssm-ec2-sg             # Security group for EC2 Instance 
SSM_EC2_NAME=ssm-ec2

# 1. Create a SSM Role and Profile for the instance EC2
prepare_SSM_role_and_profile $SSM_EC2_ROLE $SSM_EC2_PROFILE

# 2. Security group + rules for port TCP 3080 (Web app) ONLY
SSM_EC2_SG_ID=$(create_sg $SSM_EC2_SG)
open_ingress_port $SSM_EC2_SG_ID "3080" "0.0.0.0/0"   # For anyone to web app

# 3. Creates an AWS Linux 2023 Instance with SSM protocol and installs Docker (user-data)
SSM_EC2_ID=$(create_instance "t3.micro" $SSM_EC2_NAME $SSM_EC2_SG_ID "" $SSM_EC2_PROFILE)

# 4. Get the public IP address and set it into .env file
SSM_EC2_IP=$(get_public_ip "$SSM_EC2_ID")
set_env SSM_EC2_IP "$SSM_EC2_IP"

echo ""
echo "=================================================="
echo "  ${SSM_EC2_NAME} instance created"
echo "  Public IP : ${SSM_EC2_IP}   (saved as SSM_EC2_IP in ${ENV_FILE})"
echo "  IAM role : ${SSM_EC2_ROLE} / Profile : ${SSM_EC2_PROFILE}"
echo "  Test access : aws ssm start-session --target ${SSM_EC2_ID} --region eu-west-3"
echo "=================================================="
echo ""
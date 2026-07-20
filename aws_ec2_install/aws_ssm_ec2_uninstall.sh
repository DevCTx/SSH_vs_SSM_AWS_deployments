#!/bin/bash
#
# Uninstall the SSM-EC2 and Jenkins-EC2 instances for SSM deployment
#
set -e
cd "$(dirname "$0")"    # Runs the script into this folder

source ./aws_shared_library.sh     # Use the AWS shared functions


#############################################################################
# Teardown: SSM-EC2-instance (+ IAM role/profile, no SSH key)
#############################################################################

SSM_EC2_ROLE=ssm-ec2-role         # Role for SSM permissions
SSM_EC2_PROFILE=ssm-ec2-profile   # Instance profile for EC2
SSM_EC2_SG=ssm-ec2-sg             # Security group for EC2 Instance 
SSM_EC2_NAME=ssm-ec2

echo ""
echo "=== Teardown SSM-EC2 instance ==="
terminate_instance "$SSM_EC2_NAME"
delete_sg "$SSM_EC2_SG"
delete_SSM_role_and_profile "$SSM_EC2_ROLE" "$SSM_EC2_PROFILE"
unset_env SSM_EC2_IP


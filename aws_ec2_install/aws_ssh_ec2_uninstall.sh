#!/bin/bash
#
# Uninstall the SSH-EC2 instance for SSH deployment
#
set -e
cd "$(dirname "$0")"    # Runs the script into this folder

source ./aws_shared_library.sh     # Use the AWS shared functions


#############################################################################
#  Teardown: SSH-EC2-instance (+ SSH key)
#############################################################################

SSH_EC2_NAME=ssh-ec2
SSH_EC2_KEY=ssh-ec2-key     # SSH KEY for connecting local jenkins to SSH-EC2 
SSH_EC2_SG=ssh-ec2-sg       # Security group for EC2 Instance 

echo ""
echo "=== Teardown SSH-EC2 instance ==="
terminate_instance "$SSH_EC2_NAME"
delete_sg "$SSH_EC2_SG"
delete_SSH_key "$SSH_EC2_KEY"
unset_env "SSH_EC2_IP"

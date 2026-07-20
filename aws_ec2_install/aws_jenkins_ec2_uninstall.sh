#!/bin/bash
#
# Uninstall the SSM-EC2 and Jenkins-EC2 instances for SSM deployment
#
set -e
cd "$(dirname "$0")"    # Runs the script into this folder

source ./aws_shared_library.sh     # Use the AWS shared functions


#############################################################################
# Teardown: Jenkins-instance
#############################################################################

JENKINS_EC2_NAME=jenkins-ec2
JENKINS_EC2_KEY=jenkins-ec2-key     # SSH KEY for connecting local to JENKINS-EC2
JENKINS_EC2_SG=jenkins-ec2-sg       # Security group for JENKINS-EC2 Instance 

echo ""
echo "=== Teardown Jenkins instance ==="
terminate_instance "$JENKINS_EC2_NAME"
delete_sg "$JENKINS_EC2_SG"
delete_SSH_key "$JENKINS_EC2_KEY"
unset_env JENKINS_EC2_IP



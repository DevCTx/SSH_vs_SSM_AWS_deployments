PREREQUISITES:
- you have a secured AWS account
- you have an IAM admin user able to generate access keys

## Installation of AWS CLI

- refer to the page according to the system : 
    https://docs.aws.amazon.com/fr_fr/cli/latest/userguide/getting-started-install.html

- on Linux, the apt packages and repositories are not maintained by AWS. They may be outdated or incompatible. AWS only guarantees its official distributions.

- For **Linux Mint 22** :
        
    ```console
    sudo apt update
    sudo apt install -y unzip curl

    cd /tmp/
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    
    unzip awscliv2.zip
    sudo ./aws/install
    rm -r awscliv2.zip aws
    
    aws --version
    # aws-cli/2.34.26 Python/3.14.3 Linux/6.17.0-20-generic exe/x86_64.linuxmint.22
    ```

## Get your AWS credentials

In the AWS Console:
- IAM → Users → your admin user → **Security credentials**
- **Access keys** → **Create access key** → *Command Line Interface (CLI)*
- **Download the .csv** (Access Key ID + Secret shown only once)

## Configure the CLI

```bash
aws configure  # paste Access Key ID, Secret, region eu-west-3, output json
aws sts get-caller-identity   # verify
```

## AWS Shared Library

Contains :
 - `init_ami_info` : get the disk size required for the Amazon Linux 2023 AMI
 - `prepare_install_docker_script` : generates a script that installs Docker, Docker Compose and Buildx on first boot with user-data in run-instance
 - `create_SSH_key` / `delete_SSH_key` : creates or deletes an SSH key pair on AWS
 - `prepare_SSM_role_and_profile` / `delete_SSM_role_and_profile` : creates or deletes the IAM role and instance profile to get SSM permissions
 - `create_sg` / `delete_sg` : creates or deletes a Security Group
 - `open_ingress_port` : authorizes an ingress rule (port + CIDR) on a Security Group
 - `create_instance` / `terminate_instance` : creates or terminates an EC2 instance with SSH key or SSM profile
 - `get_public_ip` : get the public IP address from an instance
 - `set_env` / `unset_env` : set or unset a key/value pair in .env


## AWS SSH-EC2 Install / Uninstall
```bash
./aws_ssh_ec2_install.sh    # to install
./aws_ssh_ec2_uninstall.sh  # to uninstall
```
This script prepares an **AWS infrastructure** to **host a Java app** deployed with **SSH** :

1. Creates a **SSH Key** (`ssh-ec2-key.pem`) to let **Jenkins** connect to it via **SSH**

2. Creates a **Security group** (`ssh-ec2-sg`) + **rules** for :
    - **port 22** (SSH) open only to your **current public IP**
    - **port 3080** (the app) open to **everyone** (0.0.0.0/0)

3. Creates **EC2 instance** with
    - an `Amazon Linux 2023` **image** in `eu-west-3` **Region** (Paris) 
    - a `t3.micro` **configuration** (2 vCPU, 1 GiB RAM, Free Tier compatible)
    - a **user-data script** which **installs Docker, Docker Compose and Buildx** and **starts the Docker daemon** at start
    - and attach the **SSH key** autorizing the SSH connection

4. Displays the **public IP** of the instance and update it into the .env file


## AWS SSM-EC2 Install / Uninstall
```bash
./aws_ssm_ec2_install.sh    # to install
./aws_ssm_ec2_uninstall.sh  # to uninstall
```
This script prepares an **AWS infrastructure** to **host a Java app** deployed with **SSM** :

1. Create a **SSM Role** (`ssm-ec2-role`) and **Profile** (`ssm-ec2-profile`) for the instance EC2 to let **Jenkins** communicate with it via **SSM**

2. Creates a **Security group** (`ssm-ec2-sg`) + **rules** for :
    - **port 3080** (the app) open to **everyone** (0.0.0.0/0)

3. Creates **EC2 instance** with
    - an `Amazon Linux 2023` **image** in `eu-west-3` **Region** (Paris) 
    - a `t3.micro` **configuration** (2 vCPU, 1 GiB RAM, Free Tier compatible)
    - a **user-data script** which **installs Docker, Docker Compose and Buildx** and **starts the Docker daemon** at start
    - and attach **SSM permissions** via an **instance-profile** autorizing the SSM communication

4. Displays the **public IP** of the instance and update it into the .env file


## AWS Jenkins-EC2 Install / Uninstall
```bash
./aws_jenkins_ec2_install.sh    # to install
./aws_jenkins_ec2_uninstall.sh  # to uninstall
```
This script prepares an **AWS infrastructure** to **host a Jenkins server** that will be **deployed with SSH** but with the **SSM permissions** to communicate with the **SSM-EC2** instance

1. Creates a **SSH Key** (`jenkins-ec2-key.pem`) to let **our server** connect to it via **SSH**

2. Creates a **Security group** (`jenkins-ec2-sg`) + **rules** for :
    - **port 22** (SSH) open only to your **current public IP**
    - **port 8080** (Jenkins UI + GitHub webhook)  open to **everyone** (0.0.0.0/0)

3. Creates **EC2 instance** with
    - an `Amazon Linux 2023` **image** in `eu-west-3` **Region** (Paris) 
    - a `t3.micro` **configuration** (2 vCPU, 1 GiB RAM, Free Tier compatible)
    - a **user-data script** which **installs Docker, Docker Compose and Buildx** and **starts the Docker daemon** at start
    - and attach the **SSH key** autorizing the SSH connection

4. Displays the **public IP** of the instance and update it into the .env file

---

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

## Mount a SSH Key, a Security Group and a EC2 Docker-ready instance

```bash
./aws_ssh_ec2_install.sh
```

This script prepares an **AWS infrastructure** to **host a Java app** behind **Jenkins**:

1. **SSH key** — creates an **EC2 key pair** `jenkins-ec2.pem`, so that **Jenkins** can **SSH** into the instance.

2. **Security Group** — creates the `jenkins-sg` **Security Group** with:
    - **port 22** (SSH) open only to your **current public IP**
    - **port 3080** (the app) open to **everyone** (0.0.0.0/0)

3. **EC2 instance** with: 
    - an `Amazon Linux 2023` **AMI** in `eu-west3` (Paris) **Region**
    - a `t3.micro` **configuration** (2 vCPU, 1 GiB RAM, Free Tier compatible)
    - a **user-data script** which **installs Docker** and **starts the daemon** at start

4. Displays the **public IP** of the instance.

5. Update **.env** (into the parent folder): 
    - write/update `EC2_IP=<ip>` without duplicating (set_env).

6. Give the final instructions :
    - shown how to load the **.env** 
    - show how to **export the SSH private key** for the Jenkins script (NOT to write in .env)


---
---
---


## Manually add the SSH credential in Jenkins:

Keep the .pem file out of the repo and add the credential to Jenkins manually (once), so no secrets pass through the code.

> *Manage Jenkins → Credentials → System → Global credentials → Add Credentials*
>
>- **Kind**: SSH Username with private key
>- **ID**: `ec2-ssh-key` (must match the Jenkinsfile)
>- **Username*: `ec2-user` (Amazon Linux) or `ubuntu`
>- **Private Key*: Paste the contents of `jenkins-ec2.pem`
>
> Create

Use it in the pipeline:
groovysshagent(['ec2-ssh-key']) {
  sh 'ssh ec2-user@$EC2_HOST "docker pull ... && docker run ..."'
}

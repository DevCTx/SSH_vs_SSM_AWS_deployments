### This repo compares SSH and SSM for AWS Deployments with 2 pipelines

This first one: **ssh-dockerhub-ec2**

- fetches the **Java App** sources from **GitHub** when triggered by a `git push` webhook
- builds the source with **Maven** on a **Jenkins** server
- builds a **Docker** image and pushes it to **Docker Hub**
- deploys this image on an **AWS EC2 instance**, pulling it from **Docker Hub** by transferring a script and variables via **SSH**
- allows the user to access the **Java app** on **EC2** via the **internet**

**ssh-dockerhub-ec2-architecture** :
![ssh-dockerhub-ec2-architecture](images/ssh-dockerhub-ec2-architecture.png)

The second: **ssm-ecr-ec2**

- fetches the **Java App** sources from **GitHub** when triggered by a `git push` webhook
- builds the source with **Maven** on a **Jenkins** server
- builds a **Docker** image and pushes it to **AWS ECR**
- generates a `docker-compose.yaml` on the fly and deploys it on an **AWS EC2 instance** via **AWS SSM**, with **no SSH key** or **open SSH port** required — authentication relies entirely on the Jenkins server's **IAM role**
- allows the user to access the **Java app** on **EC2** via the **internet**

**ssm-ecr-ec2-architecture** :
![ssm-ecr-ec2-architecture](images/ssm-ecr-ec2-architecture.png)

---
### To test these pipelines, it requires some infra configurations :
1. **Fork or duplicate this repo** on your own account
2. **Prepare GitHub** : token for Jenkins and env vars
3. **Prepare DockerHub** : token for Jenkins and env vars
4. **Prepare a Server** with **Jenkins as controller** and **4 docker agents**
5. **Prepare the instances** receiving the app on **AWS**
6. **Prepare Jenkins** to be accessible from **GitHub** for webhook

I tried to automate these steps as much as possible while keeping a minimum of them manual, to make each stage easier to understand.

If you appreciate this work, please **follow** and **star this repo**. **Thanks!**

---


# 1. Fork or Create a New Repository on GitHub

This step is required in order to obtain your own webhook for Jenkins. 

Fork :
```bash
env gh repo fork https://github.com/DevCTx/SSH_vs_SSM_AWS_Deployments --clone
```

Or alternatively, clone this repository, delete the Git history and move the source code to a new repository.

```bash
git clone https://github.com/DevCTx/SSH_vs_SSM_AWS_Deployments
cd SSH_vs_SSM_AWS_Deployments
rm -rf .git     # deletes all links with git

git init                    # start a fresh repository
git add .
git commit -m "Initial commit"
git branch -M main

# Use your GitHub Account 
env gh repo create <your_GitHub_account>/SSH_vs_SSM_AWS_Deployments \
  --public \
  --description "Full CI/CD pipeline for a Java application: triggered by a GitHub webhook on push, built with Maven on Jenkins, automatic image tagging, push to DockerHub or AWS ECR, and deployment to AWS EC2 via SSH or SSM." \
  --source=. \
  --push
```

If you reuse this repo or a part of it, please keep this attribution.
```
### Credits
Sources: [DevCTx/SSH_vs_SSM_AWS_Deployments](https://github.com/DevCTx/SSH_vs_SSM_AWS_Deployments).
```

---

# 2. GitHub Configuration

### 2.1. Generate a GitHub token (PAT)

> *Profile > Settings > Developer settings > Personal access tokens > Fine-grained tokens > Generate new token*

- **Token name**: `jenkins-token` 
- **Description**: `Jenkins Token for SSH_vs_SSM_AWS_Deployments repository` 
- **Resource owner**: `<your GitHub account>` 
- **Expiration**: `7 days` or more if needed 
- **Repository Access**: Select **only** the `SSH_vs_SSM_AWS_Deployments` repository 
- **Repository permissions** (everything else on *No access*) :

>| Permission | Level | Why |
>|---|---|---|
>| Contents | Read-only | clone / checkout the sources |
>| Metadata | Read-only | required by default (auto) |
>| Commit statuses | Read and write | post the CI status on commits |
>| Webhooks | Read and write | Manage the hooks for a repository |

*Click `Generate token`** and **copy the token** (displayed only once).

### 2.2. Save it into a .env file

```
GITHUB_JENKINS_TOKEN=<github_pat_xxx>
GITHUB_OWNER=<your GitHub account>
REPO=<your GitHub account>/SSH_vs_SSM_AWS_Deployments
```
---

### 2.3. Test it

```
chmod 744 ./test_github_config.sh
./test_github_config.sh
```
*you should see :*
```
✅ GITHUB_JENKINS_TOKEN matches GITHUB_OWNER (<your GitHub account>)
✅ REPO '<your GitHub account>/SSH_vs_SSM_AWS_Deployments' is accessible
```

---

# 3. Docker Hub Configuration

- Create an account or Log into your account on https://hub.docker.com/

### 3.1. Generate a DockerHub token

> *Account Settings > Personal Access Tokens > New access token*

- **Access Token Description**: `jenkins-myapp` 
- **Expiration Date**: `30 days` 
- **Access Permissions**: `Read, Write & Delete` 

*Click `Generate`** and **copy the token** (displayed only once).

### 3.2. Save it into the .env file

```
DOCKER_USERNAME=<your Docker Hub account>
DOCKERHUB_PAT=<dckr_pat_xxx>
```

### 3.3. Test it

```bash
chmod 744 ./test_dockerhub_config.sh
./test_dockerhub_config.sh
```
you should see the message : `Login Succeeded`

---

# 4. AWS Configuration

Prerequisites:
- an AWS account and an IAM administrator user who can generate access keys

- AWS CLI installed - if not, please refer to the page according to your system : \
https://docs.aws.amazon.com/fr_fr/cli/latest/userguide/getting-started-install.html


### 4.1. Get your AWS credentials

Login to the AWS Console with your admin user account

> *IAM > Users > Your Admin User > Security credentials > Access keys > Create access key*
- select **Command Line Interface (CLI)**
- **Description** : `jenkins-ci`
- **Copy** the credentials or **Download the .csv** out of the repo 

Click **Done**

### 4.2. Configure the CLI

```bash
aws configure  # paste Access key, Secret access key, region eu-west-3, output json
```

### 4.3. Test it
```bash
aws sts get-caller-identity   
```
*you should see :*
```
aws sts get-caller-identity 
{
    "UserId": "AIDAI...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-user"
}
```

---

# 5. Run Jenkins CI > Docker Hub > AWS EC2 via SSH

### 5.1. Prepare the AWS EC2 with SSH authorization


```
chmod 744 ./aws_ssh_ec2_install/aws_ssh_ec2_install.sh
./aws_ssh_ec2_install/aws_ssh_ec2_install.sh
```

This script will :
- create an **SSH key** `jenkins-ec2.pem` if missing
- create a **Security Group** and open ports **22** (for your IP) and **3080** (public)
- calculate the **minimal disk size** required for the app on an **Amazon Linux 2023** instance
- create an **EC2 instance** with an **Amazon Linux 2023 AMI** in the **eu-west-3** Region (Paris), on a **t3.micro** configuration (2 vCPU, 1 GiB RAM, Free Tier compatible) and the **appropriate volume size**
- install **Docker** and start the daemon on boot
- retrieve the **public IP** and set it into the **.env** file as **EC2_IP**


### 5.2 Install the Jenkins Server with an SSH environment 

```
chmod 744 ./jenkins_install/docker_jenkins_platform_install.sh
sudo ./jenkins_install/docker_jenkins_platform_install.sh
```

This script will :
- verify if **Docker** is available or install on host if missing 
- prepare the architecture 
  ```
  └── jenkins
      ├── docker-compose.yaml
      ├── agents
      │   ├── aws/Dockerfile       # AWS deployment (AWS CLI v2)
      │   ├── docker/Dockerfile    # DockerHub Deployments (host socket access)
      │   └── maven/Dockerfile     # Java builds (JDK 21 + Maven)
      └── controller               # orchestration only, web UI
          ├── Dockerfile
          └── jenkins-config.yaml
  ```
- ask an **admin account username**, **generate a strong password**, and store them in **.env**

- build and tests the **agent images** (docker-agent, maven-agent, aws-agent) and pull the inbound agent for the base-agent image

- check if the `jenkins-ec2.pem`SSH key is available

- Then **build the comtroller** running the **JCasc** `jenkins-config.yaml` file to: 
  
  - install **Jenkins as controller** into a docker container 
  
  - install and test **4 docker agents** (base, docker, maven and aws cli).
    - **base-agent**: for simple operations like git
    - **maven-agent**: for building the java source as .JAR
    - **docker-agent**: for building JAR as docker image and store it on Docker Hub
    - **aws-agent**: for deploying to the AWS EC2 instance via SSH
  
  - install the required **credentials** (GitHub Token, DockerHub, EC2 IP and SSH Key)
    > *The `jenkins-ec2.pem` SSH key is mounted as **volume** and used as **secret** into Jenkins (not stored in .env) because its multi-line format would break the .env parsing*

  - pre-configure **2 operational pipelines** :
  
    - `agent testings`: to **test each agent** from Jenkins before to start  
  
    - `ssh-dockerhub-ec2` : a **full CI/CD** triggered from GitHub push, building source and pushing the image to dockerhub before to pull it from the EC2 instance. 


### After the installation :
- **Open** `http://<jenkins-ip>:8080` \
- **Enter** your admin `username` and the generated `password` \
- *Optional* : **Build** the `agent-testings` pipeline to test the docker agents from Jenkins
  On `<Build pipeline>` into Jenkins :
    ![ssh-dockerhub-ec2](images/agent-testings-jenkins.png)


- Before the run the CI/CD pipelines, Jenkins need to have a public IP.

### 5.3 Update the GitHub Webhook with a public IP (or set it with Cloudflare)

```
chmod 744 ./jenkins_install/setup_github_webhook.sh
./jenkins_install/setup_github_webhook.sh
```

This script will 
 - **Load env**: sources .env, requires `GITHUB_JENKINS_TOKEN` + `REPO`

 - **Get public URL for Jenkins** : asks if Jenkins has a public IP; 
   - if yes => use the local IP address,
   - if no => install Cloudflare and create a public IP tunnel. 
 - **Create or update the** `github-webhook` to let a `git push` triggered the Jenkins pipeline.


### 5.4 Trigger a CI/CD run and verify the deployment !

```
chmod 744 ./test_deployments.sh
./test_deployments.sh
```

This script will : 

- **Load env**: DOCKER_USERNAME, DOCKERHUB_PAT, EC2_IP from .env;
- **Get the last tag** from DockerHub before the push
- **Trigger the pipeline** with an empty commit and git push
- **Wait for the build on Jenkiins and new tag on Docker Hub**
- **Wait for cleanup on Docker Hub**
- **Verify EC2**: connect via SSH and check if the image tag running the container is the last created

### *On Jenkins, you should see*
![ssh-dockerhub-ec2](images/ssh-dockerhub-ec2-jenkins.png)

### *On DockerHub, you should see*
![demo-java-app](images/demo-java-app-dockerhub.png)

### *On EC2, you should see*
![java-app-docker-ec2](images/java-app-docker-ec2.png)

### *On internet, you should see*
![java-app-web](images/java-app-web.png)


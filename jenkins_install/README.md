# Install Script : Jenkins Docker Platform (JCasC, zero manual setup)

Installs a Full Jenkins CI/CD platform: controller + 4 on-demand agents (base, Docker, Maven, AWS), \
auto-configured via **Configuration-as-Code** (JCasC) — with minimal manual setup.
 
## Architecture
 
```
controller (web UI, orchestration only, numExecutors: 0)
  └── Docker Cloud plugin → spawns agents on demand
        ├── base-agent    (for simple use of inbound-agent)
        ├── docker-agent  (Docker CLI, host socket access)
        ├── maven-agent   (JDK 21 + Maven)
        └── aws-agent     (AWS CLI v2)
```
 
Agents are ephemeral containers, **created/destroyed automatically** by the
**Docker Cloud** plugin.

## Plugins
 
| Plugin | Purpose |
|---|---|
| `workflow-aggregator` | supports Jenkinsfile with pipeline{}, stages ... |
| `pipeline-stage-view` | shows the progress of pipeline stages |
| `configuration-as-code` | auto-load `jenkins-config.yaml` at startup |
| `job-dsl` | allows defining Jenkins jobs/pipelines as code (with `.groovy`) |
| `docker-plugin` | allows on-demand Docker Cloud agents |
| `github` | allows webhook via git push |
| `git` | allows Jenkins to clone/checkout Git sources |
| `credentials-binding` | allows `withCredentials` for Docker/AWS |
| `ssh-credentials` | allows to store the SSH Key for EC2 |
| `ssh-agent` | provides the sshagent step for SSH deployments |
| `ws-cleanup` | allows the cleanWs() step to clean after stage|
| `matrix-auth` | enables JCasC to define user permissions (admin here) |

## Result structure
 
```
.
├── docker_jenkins_platform_install.sh
├── docker_jenkins_platform_uninstall.sh
├── cf.log
├── README.md
└── jenkins
    ├── docker-compose.yaml
    ├── agents
    │   ├── aws/Dockerfile       # AWS deployment (AWS CLI v2)
    │   ├── docker/Dockerfile    # build & push Docker images (host socket access)
    │   └── maven/Dockerfile     # Java builds (JDK 21 + Maven)
    └── controller               # orchestration only, web UI, CI/CD plugins
        ├── Dockerfile
        └── jenkins-config.yaml
```

## Usage
 
```bash
sudo ./docker_jenkins_platform_install.sh
```

At the end, the script displays the address of the Jenkins server `http://<host-ip>:8080` and indicates the `admin password` to enter at the first use.


## What it does

The script:
1. Installs **Docker CE** from the official repo (only if absent).
2. Generates the **JCasC config** (Docker Cloud + 3 agent templates).
3. Builds the **controller** from `jenkins/jenkins:lts` and **agent images** (Docker, Maven, AWS CLI).
4. **Tests** each agent image (`docker --version`, `mvn -v`, `aws --version`).
5. **Starts** the controller via `docker compose up -d --build`.
6. Prints the **Jenkins URL** and the **admin login/password** (from .env).


## Key design

- **Docker-outside-of-Docker (DooD)**: `/var/run/docker.sock` is mounted into the controller
  and `docker-agent` with `DOCKER_GID` aligned, so `jenkins` can drive the host's Docker daemon **without to be root**. \
  => *The socket gives access, the GID gives permission.*

- **JCasC**: `jenkins-config.yaml` is copied into the controller image and loaded via `CASC_JENKINS_CONFIG` — the Docker Cloud and agent templates exist as soon as Jenkins starts, no manual node creation.

## Pre-configured credentials (via JCasC)

| ID | Type | Source |
|---|---|---|
| `DOCKER_USERNAME` | secret text | `.env` |
| `dockerhub-pat` | secret text | `.env` |
| `MY_INSTANCE_EC2_IP` | secret text | `.env` |
| `EC2_SSH_KEY` | SSH private key | mounted `.pem` file |
| `github-token` | username/password | `.env` |


## Requirements

- Ubuntu-based host, `sudo` rights
- On Linux Mint, the repo uses `UBUNTU_CODENAME` (`noble`), not `VERSION_CODENAME`


## Ports

| Port | Use |
|---|---|
| 8080 | web UI (must be free or remap the line `-p 8080:8080` to `-p 8081:8080`) |
| 50000 | inbound agent connections |

## After installation

- The script will ask for a Jenkins **admin username** (first run only) and generate a strong **password**, both saved in `.env`
- **Open** `http://<host-ip>:8080` and log in with these credentials

## Test the agents from a Jenkins pipeline (Automatically initiated)

The agents are automatically tested during the installation via a docker command but a pipeline is also created with JCasC reproducing these steps to test them via Jenkins directly => just **Click `<Build the pipeline>`**

Reproducing: **Jenkins > New Item** 

- Enter a name : `agent-testings`
- Select : `pipeline`
- Into **Configuration > Pipeline** :
    - Definition : **Pipeline Script**
        
        ```bash
        pipeline {
            agent none
            
            stages {
               stage('Test Base')
               {
                  agent { label 'base-agent' }
                  steps { sh 'java -version && git --version' }
               }
               stage('Test Maven')
               {
                  agent { label 'maven-agent' }
                  steps { sh 'mvn -v' }
               }
               stage('Test Docker')
               {
                  agent { label 'docker-agent' }
                  steps { sh 'docker --version' }
               }
               stage('Test AWS CLI')
               {
                  agent { label 'aws-agent' }
                  steps { sh 'aws --version' }
               }
            }
        }
        ```
    - **Save** 

- **Click `<Build the pipeline>`**

 
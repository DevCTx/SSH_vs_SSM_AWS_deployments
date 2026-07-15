# Install Script : Jenkins Docker Platform (JCasC, zero manual setup)

Installs a Full Jenkins CI/CD platform: controller + 4 on-demand agents (base, Docker, Maven, AWS), \
auto-configured via **Configuration-as-Code** (JCasC) — with minimal manual setup.
 
## Architecture
 
```
controller (web UI, orchestration only, numExecutors: 2)
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
| `git` | allows Jenkins to clone/checkout Git sources |
| `pipeline-stage-view` | shows the progress of pipeline stages |
| `credentials-binding` | allows `withCredentials` for Docker/AWS |
| `ssh-credentials` | allows to connect to EC2 via SSH |
| `ssh-slaves` | allows to run Jenkins agents via SSH on EC2 |
| `docker-plugin` | allows on-demand Docker Cloud agents |
| `configuration-as-code` | auto-load `jenkins-config.yaml` at startup |
| `job-dsl` | allows defining Jenkins jobs/pipelines as code (with `.groovy`) |

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
6. **Prints** the **Jenkins URL** and **initial admin password**.


## Key design

- **Docker-outside-of-Docker (DooD)**: `/var/run/docker.sock` is mounted into the controller
  and `docker-agent` with `DOCKER_GID` aligned, so `jenkins` can drive the host's Docker daemon **without to be root**. \
  => *The socket gives access, the GID gives permission.*

- **JCasC**: `jenkins-config.yaml` is copied into the controller image and loaded via `CASC_JENKINS_CONFIG` — the Docker Cloud and agent templates exist as soon as Jenkins starts, no manual node creation.

## Requirements

- Ubuntu-based host, `sudo` rights
- On Linux Mint, the repo uses `UBUNTU_CODENAME` (`noble`), not `VERSION_CODENAME`


## Ports

| Port | Use |
|---|---|
| 8080 | web UI (must be free or remap the line `-p 8080:8080` to `-p 8081:8080`) |
| 50000 | inbound agent connections |

## After installation

- **Open** `http://<host-ip>:8080` and **enter** the displayed `admin password`
- **Install** the `suggested plugins` from Jenkins
- **Set** a `username` and `password` for the Jenkins server

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

 
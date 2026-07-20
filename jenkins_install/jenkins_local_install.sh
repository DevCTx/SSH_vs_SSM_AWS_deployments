#!/bin/bash
#
#####################################################################################################
#
# Installs a full Jenkins Docker platform (controller + agents) via docker compose + JCasC (zero manual setup)
#
# Installs Docker CE from the official repo (only if absent), then builds and runs, then:
#   - builds the controller image (self-configured through Configuration-as-Code)
#   - builds the 3 agent images used on demand by the Docker Cloud (docker, maven, aws)
#   - starts the controller with docker compose
#
# Plugins required:
#   - workflow-aggregator : to support Jenkinsfile with pipeline{}, stages ...
#   - git : allows Jenkins to clone/checkout Git sources
#   - pipeline-stage-view : show the progress of pipeline stages
#   - credentials-binding : allows 'with credentials' for docker and aws
#   - ssh-slaves : allow to connect agents via SSH for EC2 deployments
#   - docker-plugin : use agents on demand as Docker containers (through Docker Cloud)
#   - configuration-as-code : auto-configure Jenkins from jenkins-config.yaml (JCasC) at startup
#
# Agents are created/attached/destroyed automatically by the Docker Cloud plugin
#
# Installation : 
#   sudo ./docker_jenkins_platform_install.sh
#
# Result: 
# .
# ├── docker_jenkins_platform_install.sh
# ├── docker_jenkins_platform_uninstall.sh
# ├── cf.log
# ├── README.md
# └── jenkins
#     ├── docker-compose.yaml
#     ├── agents
#     │   ├── aws/Dockerfile       # AWS deployment (AWS CLI v2)
#     │   ├── docker/Dockerfile    # build & push Docker images (host socket access)
#     │   └── maven/Dockerfile     # Java builds (JDK 21 + Maven)
#     └── controller               # orchestration only, web UI, CI/CD plugins
#         ├── Dockerfile
#         └── jenkins-config.yaml
# 
#####################################################################################################

set -e                  # Stop the script if an error appears
cd "$(dirname "$0")"    # Runs the script into this folder

# Export all variables from .env
ENV_FILE="$(pwd)/../.env"
set -a; source "$ENV_FILE"; set +a   # reload the .env for the new vars

####################################################################################################
# PREREQUISITES : Install Docker on the host if it does not exist yet
####################################################################################################

command -v docker >/dev/null || {
  if [ -f /etc/debian_version ]; then
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Dépôt Docker : use VERSION_CODENAME=zena or UBUNTU_CODENAME=noble (Ubuntu) according to your sys
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list

    # Installation
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    yum install -y docker
  fi
}
# Start and Enable Docker Daemon on startup
systemctl enable --now docker

####################################################################################################
# Structure
####################################################################################################

mkdir -p ./jenkins/controller
mkdir -p ./jenkins/agents/{docker,maven,aws}
cd ./jenkins

####################################################################################################
# JCasC config : Docker Cloud + agent templates (auto-loaded at startup)
####################################################################################################

cat > controller/jenkins-config.yaml <<'EOF'
jenkins:
  numExecutors: 0            # controller orchestrates only, never builds
  
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "${JENKINS_ADMIN_USER}"
          password: "${JENKINS_ADMIN_PASSWORD}"
  authorizationStrategy:
    globalMatrix:
      entries:
        - user:
            name: "${JENKINS_ADMIN_USER}"
            permissions:
              - "Overall/Administer"

  clouds:
    - docker:
        name: "docker-cloud"
        dockerApi:
          dockerHost:
            uri: "unix:///var/run/docker.sock"    
  
        templates:
 
          - labelString: "base-agent"
            dockerTemplateBase: { image: "jenkins/inbound-agent" }
            remoteFs: "/home/jenkins"
            connector: { attach: {} }
            pullStrategy: PULL_NEVER
            instanceCapStr: "2"
            
          - labelString: "maven-agent"
            dockerTemplateBase: { image: "jenkins-maven-agent" }
            remoteFs: "/home/jenkins"
            connector: { attach: {} }
            pullStrategy: PULL_NEVER
            instanceCapStr: "2"
 
          - labelString: "aws-agent"
            dockerTemplateBase: { image: "jenkins-aws-agent" }
            remoteFs: "/home/jenkins"
            connector: { attach: {} }
            pullStrategy: PULL_NEVER
            instanceCapStr: "2"
 
          - labelString: "docker-agent"
            dockerTemplateBase:
              image: "jenkins-docker-agent"
              mounts:                              # Give Access to the host's Docker daemon
                - "type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock"
              extraGroups: [ "${DOCKER_GID}" ]     # Give Permissions to use docker socket
            remoteFs: "/home/jenkins"
            connector: { attach: {} }
            pullStrategy: PULL_NEVER
            instanceCapStr: "2"

credentials:
  system:
    domainCredentials:
      - credentials:
          # Docker Hub (secret text)
          - string: { scope: GLOBAL, id: "DOCKER_USERNAME", secret: "${DOCKER_USERNAME}" }
          - string: { scope: GLOBAL, id: "dockerhub-pat",   secret: "${DOCKERHUB_PAT}" }
          # EC2 public IP (secret text)
          - string: { scope: GLOBAL, id: "MY_INSTANCE_EC2_IP", secret: "${SSH_EC2_IP}" }
          # EC2 SSH private key: read from the .pem mounted read-only into the controller.
          - basicSSHUserPrivateKey:
              scope: GLOBAL
              id: "EC2_SSH_KEY"
              username: "ec2-user"
              privateKeySource:
                directEntry:
                  privateKey: "${readFile:/run/secrets/ec2_key.pem}"
          # GitHub PAT for the shared library + checkout
          - usernamePassword:
              scope: GLOBAL
              id: "github-token"
              username: "${GITHUB_OWNER}"
              password: "${GITHUB_JENKINS_TOKEN}"

jobs:

  # 1. AGENT TESTS: a pipeline that tests the 3 agents (inline script, no repo needed)
  - script: >
      pipelineJob('agent-testings') {
        definition {
          cps {
            sandbox(true)
            script('''
              pipeline {
                agent none
                stages {
                  stage('Test Base')    {
                    agent { label 'base-agent' }
                    steps { sh 'java -version && git --version' }
                  }
                  stage('Test Maven')   {
                    agent { label 'maven-agent' }
                    steps { sh 'mvn -v' }
                  }
                  stage('Test Docker')  {
                    agent { label 'docker-agent' }
                    steps { sh 'docker --version' }
                  }
                  stage('Test AWS CLI') {
                    agent { label 'aws-agent' }
                    steps { sh 'aws --version' }
                  }
                }
              }
            '''.stripIndent())
          }
        }
      }

  - script: >
      pipelineJob('ssh-dockerhub-ec2') {
        triggers {
          githubPush()
        }
        definition {
          cpsScm {
            scm {
              git {
                remote {
                  url("https://github.com/${REPO}.git")
                  credentials('github-token')
                }
                branch('*/main')
              }
            }
            scriptPath('ssh_dockerhub_ec2/Jenkinsfile')
          }
        }
      }
EOF


####################################################################################################
# Jenkins Controller 
####################################################################################################

cat > ./controller/Dockerfile <<'EOF'
FROM jenkins/jenkins:lts

USER root

# runSetupWizard=false to unable Jenkins preconfiguration and only install the required plugins
# Dhudson.model.DirectoryBrowserSupport.CSP : to enforce Content Security Policy (CSP) (recommanded by Jenkins)
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.model.DirectoryBrowserSupport.CSP=\"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:\""

# Essential Plugins for these CI/CD
RUN jenkins-plugin-cli --plugins \
    workflow-aggregator \
    git \
    github \
    pipeline-stage-view \
    credentials-binding \
    ssh-credentials \
    ssh-slaves \
    ssh-agent \
    ws-cleanup \
    docker-plugin \
    configuration-as-code \
    job-dsl \
    matrix-auth

# Auto-load the JCasC config at startup
COPY jenkins-config.yaml /var/jenkins_home/casc/jenkins-config.yaml
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc/jenkins-config.yaml

USER jenkins
EOF

####################################################################################################
# Docker Agent 
####################################################################################################

cat > ./agents/docker/Dockerfile <<'EOF'
FROM jenkins/inbound-agent

USER root

ARG DOCKER_GID=999

RUN apt-get update && apt-get install -y \
    git \
    curl \
    docker.io \
    ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# If(docker group exists)-> modification of its GID, else -> we create it, then add jenkins to it
RUN getent group docker \
    && groupmod -g ${DOCKER_GID} docker \
    || groupadd -g ${DOCKER_GID} docker \
    &&  usermod -aG docker jenkins

USER jenkins
EOF

####################################################################################################
# Maven Agent
####################################################################################################

cat > ./agents/maven/Dockerfile <<'EOF'
FROM jenkins/inbound-agent

USER root

RUN apt-get update && apt-get install -y \
    openjdk-21-jdk \
    maven \
    git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
EOF

####################################################################################################
# AWS Agent
####################################################################################################

cat > ./agents/aws/Dockerfile <<'EOF'
FROM jenkins/inbound-agent

USER root

RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    git \
    ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

USER jenkins
EOF

####################################################################################################
# docker-compose.yaml  (one service per box in the diagram)
####################################################################################################

cat > docker-compose.yaml <<'EOF'
services:
 
  controller:
    build:
      context: ./controller
      args: { DOCKER_GID: "${DOCKER_GID}" }
    image: jenkins-controller
    container_name: jenkins
    init: true
    restart: unless-stopped
    ports:
      - "8080:8080"       # web UI port
      - "50000:50000"     # indbound agent port
    group_add:
      - "${DOCKER_GID}"   # access to Docker socket
    environment:          # for jenkins-config.yaml
      DOCKER_GID: "${DOCKER_GID}"
      REPO: "${REPO}"
      GITHUB_OWNER: "${GITHUB_OWNER}"
      GITHUB_JENKINS_TOKEN: "${GITHUB_JENKINS_TOKEN}"
      DOCKER_USERNAME: "${DOCKER_USERNAME}"
      DOCKERHUB_PAT: "${DOCKERHUB_PAT}"
      SSH_EC2_IP: "${SSH_EC2_IP}"
      JENKINS_ADMIN_USER: "${JENKINS_ADMIN_USER}"
      JENKINS_ADMIN_PASSWORD: "${JENKINS_ADMIN_PASSWORD}"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock  # Access to the host's Docker daemon
      - jenkins_home:/var/jenkins_home	           # persists Jenkins data
      - ../../aws_ec2_install/ssh-ec2-key.pem:/run/secrets/ec2_key.pem:ro

volumes:
  jenkins_home: {}		 # {} = explicite empty object
EOF


####################################################################################################
# Jenkins admin account (username + strong generated password, persisted in .env)
####################################################################################################

set_env() {
  grep -v "^$1=" "$ENV_FILE" 2>/dev/null > "$ENV_FILE.tmp" || true
  echo "$1=$2" >> "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
}

if ! grep -q "^JENKINS_ADMIN_USER=" "$ENV_FILE" 2>/dev/null; then
  read -p "Define a Jenkins admin username: " ADMIN_USER
  set_env JENKINS_ADMIN_USER "$ADMIN_USER"
fi

if ! grep -q "^JENKINS_ADMIN_PASSWORD=" "$ENV_FILE" 2>/dev/null; then
  ADMIN_PASSWORD=$(openssl rand -base64 24)
  set_env JENKINS_ADMIN_PASSWORD "$ADMIN_PASSWORD"
  echo "🔑 Generated Jenkins admin password: $ADMIN_PASSWORD"
fi

set -a; source "$ENV_FILE"; set +a   # reload the .env for the new vars


####################################################################################################
# Build agent images (used locally by the cloud, PULL_NEVER) + start controller
####################################################################################################

# Get the Docker GID
export DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
echo "DOCKER_GID=${DOCKER_GID}"

docker build --build-arg DOCKER_GID=$DOCKER_GID -t jenkins-docker-agent ./agents/docker
docker build -t jenkins-maven-agent ./agents/maven
docker build -t jenkins-aws-agent   ./agents/aws

####################################################################################################
# Ensure base-agent image is present locally (PULL_NEVER needs it pre-pulled)
####################################################################################################

docker pull jenkins/inbound-agent

####################################################################################################
# Test agent images
####################################################################################################

test_agent () {
  echo ""
  echo "=== Testing $1 ==="
  docker run --rm --entrypoint bash "${@:3}" "$1" -c "$2"
}

test_agent jenkins/inbound-agent "java -version && git --version"
test_agent jenkins-docker-agent "docker --version" -v /var/run/docker.sock:/var/run/docker.sock
test_agent jenkins-maven-agent  "mvn -v"
test_agent jenkins-aws-agent    "aws --version"

####################################################################################################
# Build and start the controller using these agents
####################################################################################################

echo ""
echo "=== Build Controller ==="

PEM_FILE="../../aws_ec2_install/ssh-ec2-key.pem"
if [ ! -f "$PEM_FILE" ]; then
  echo "$PEM_FILE not found. Please run aws_ec2_install.sh before."
  exit 1
fi

docker compose up -d --build

echo ""
echo "Waiting 15s for the Jenkins controller to start..."
sleep 15

####################################################################################################
# Detect if the script is running on a AWS instance 
####################################################################################################
IS_AWS=false

echo ""
echo "Detect if the script is running on a AWS instance ..."

# Get AWS metadata token (IMDSv2)
# 169.254.169.254 is a special address accessible only from the server
TOKEN=$(curl -s --max-time 1 -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
[ -n "$TOKEN" ] && IS_AWS=true

if $IS_AWS; then
  echo "Detected: running on AWS EC2"
  JENKINS_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/public-ipv4)
else
  echo "Detected: running locally"
  JENKINS_IP="$(hostname -I | awk '{print $1}')"
fi

set_env JENKINS_IP "$JENKINS_IP"

echo ""
echo "✅ Jenkins ready: http://$JENKINS_IP:8080"
echo "🔑 Login : $JENKINS_ADMIN_USER / password : $JENKINS_ADMIN_PASSWORD"

echo ""
echo "The Docker Cloud and its 3 agents (docker, maven and aws) should be configured into Jenkins."
echo "and you should be able to test them by building the agent-testings pipeline"
echo ""

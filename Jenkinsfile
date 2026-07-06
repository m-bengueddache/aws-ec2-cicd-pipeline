#!/usr/bin/env groovy

def imageName

pipeline {
    agent any
    tools {
        maven 'maven'
    }
    environment {
        ECR_REGISTRY   = credentials('ecr-registry-url')   // e.g. <account-id>.dkr.ecr.<region>.amazonaws.com
        ECR_REPO       = 'demo-app'
        EC2_HOST       = credentials('ec2-deploy-host')    // e.g. ec2-user@<public-ip>
    }
    stages {
        stage('increment version') {
            steps {
                script {
                    sh '''
                        mvn build-helper:parse-version versions:set \
                        -DnewVersion=\\${parsedVersion.majorVersion}.\\${parsedVersion.minorVersion}.\\${parsedVersion.nextIncrementalVersion} \
                        versions:commit
                    '''
                    def matcher = readFile('pom.xml') =~ '<version>(.+)</version>'
                    def version = matcher[0][1]
                    imageName = "${ECR_REGISTRY}/${ECR_REPO}:${version}-${BUILD_NUMBER}"
                }
            }
        }
        stage('build app') {
            steps {
                sh 'mvn clean package'
            }
        }
        stage('build & push image') {
            steps {
                script {
                    sh "docker build -t ${imageName} ."
                    withCredentials([usernamePassword(credentialsId: 'ecr-credentials', usernameVariable: 'USER', passwordVariable: 'PASS')]) {
                        sh "echo \$PASS | docker login --username \$USER --password-stdin ${ECR_REGISTRY}"
                    }
                    sh "docker push ${imageName}"
                }
            }
        }
        stage('deploy') {
            steps {
                script {
                    def repo = "${ECR_REGISTRY}/${ECR_REPO}"
                    def tag  = imageName.substring(repo.length() + 1)
                    sshagent(['ec2-server-key']) {
                        sh "scp -o StrictHostKeyChecking=no server-cmds.sh docker-compose.yaml ${EC2_HOST}:/home/ec2-user"
                        sh "ssh -o StrictHostKeyChecking=no ${EC2_HOST} 'bash ./server-cmds.sh ${repo} ${tag}'"
                    }
                }
            }
        }
        stage('commit version update') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'git-credentials', usernameVariable: 'USER', passwordVariable: 'PASS')]) {
                    sh '''
                        git config user.email "jenkins@example.com"
                        git config user.name "jenkins"
                        git remote set-url origin https://${USER}:${PASS}@github.com/m-bengueddache/aws-ec2-cicd-pipeline.git
                        git add pom.xml
                        git commit -m "ci: version bump"
                        git push origin HEAD:main
                    '''
                }
            }
        }
    }
}

pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: docker
    image: docker:24.0.7-dind
    securityContext:
      privileged: true
    env:
    - name: DOCKER_TLS_CERTDIR
      value: ""
    - name: DOCKER_HOST
      value: "tcp://localhost:2375"
  - name: kubectl
    image: bitnami/kubectl:1.31
    command:
    - cat
    tty: true
  - name: node
    image: node:20-alpine
    command:
    - cat
    tty: true
  - name: aws-cli
    image: amazon/aws-cli:latest
    command:
    - cat
    tty: true
"""
        }
    }

    environment {
        AWS_REGION = 'eu-west-1'
        ECR_REPOSITORY = 'demoapp'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        AWS_PROFILE = 'rotem-poc'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install Dependencies') {
            steps {
                container('node') {
                    sh '''
                        npm install
                    '''
                }
            }
        }

        stage('Run Tests') {
            steps {
                container('node') {
                    sh '''
                        npm test
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                container('docker') {
                    script {
                        sh '''
                            dockerd-entrypoint.sh &
                            sleep 10
                            docker build -f docker/Dockerfile -t ${ECR_REPOSITORY}:${IMAGE_TAG} .
                            docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${ECR_REPOSITORY}:latest
                        '''
                    }
                }
            }
        }

        stage('Push to ECR') {
            steps {
                container('aws-cli') {
                    withCredentials([aws(credentialsId: 'aws-credentials')]) {
                        sh '''
                            AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                            aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                            docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}
                            docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}

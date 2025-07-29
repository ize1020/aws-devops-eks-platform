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
  - name: node
    image: node:20-alpine
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

        stage('Security Scan') {
            steps {
                container('node') {
                    sh '''
                        npm audit --audit-level=high || true
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
                container('docker') {
                    withCredentials([aws(credentialsId: 'aws-credentials')]) {
                        sh '''
                            # Install AWS CLI in docker container
                            apk add --no-cache aws-cli
                            
                            # Get AWS Account ID
                            AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                            echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
                            
                            # Login to ECR
                            aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                            
                            # Tag and push image
                            docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}
                            docker tag ${ECR_REPOSITORY}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:latest
                            docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}
                            docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:latest
                            
                            echo "🎉 Docker image successfully pushed to ECR!"
                            echo "✅ Image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}"
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
        success {
            echo '🎉 CI Pipeline completed successfully!'
            echo '✅ Code built, tested, and pushed to ECR!'
            echo '📦 Ready for deployment!'
        }
        failure {
            echo '❌ CI Pipeline failed. Check logs for details.'
        }
    }
}

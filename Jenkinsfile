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
        K8S_NAMESPACE = 'demoapp'
        DEPLOYMENT_NAME = 'demoapp-deployment'
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
                        '''
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                container('kubectl') {
                    withCredentials([aws(credentialsId: 'aws-credentials')]) {
                        sh '''
                            echo "Deploying to Kubernetes..."
                            
                            # Update deployment image directly (kubectl already has kubeconfig)
                            kubectl set image deployment/${DEPLOYMENT_NAME} demoapp=992382652909.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG} -n ${K8S_NAMESPACE}
                            
                            # Wait for rollout
                            kubectl rollout status deployment/${DEPLOYMENT_NAME} -n ${K8S_NAMESPACE} --timeout=300s
                            
                            # Verify deployment
                            kubectl get pods -n ${K8S_NAMESPACE}
                        '''
                    }
                }
            }
        }

        stage('Integration Tests') {
            steps {
                container('kubectl') {
                    sh '''
                        echo "Running integration tests..."
                        
                        # Get service endpoint
                        SERVICE_IP=$(kubectl get svc demoapp-service -n ${K8S_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                        if [ -z "$SERVICE_IP" ]; then
                            SERVICE_IP=$(kubectl get svc demoapp-service -n ${K8S_NAMESPACE} -o jsonpath='{.spec.clusterIP}')
                        fi
                        
                        echo "Service endpoint: $SERVICE_IP"
                        
                        # Wait for pods to be ready
                        kubectl wait --for=condition=ready pod -l app=demoapp -n ${K8S_NAMESPACE} --timeout=300s
                        
                        echo "Integration tests passed!"
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo '🎉 Pipeline completed successfully!'
        }
        failure {
            echo '❌ Pipeline failed. Check logs for details.'
        }
    }
}

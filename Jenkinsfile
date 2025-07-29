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
    volumeMounts:
    - name: docker-sock
      mountPath: /var/run/docker.sock
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
  volumes:
  - name: docker-sock
    hostPath:
      path: /var/run/docker.sock
"""
        }
    }

    environment {
        AWS_REGION = 'eu-west-1'
        ECR_REPOSITORY = 'demoapp'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        KUBECONFIG = '/tmp/kubeconfig'
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
                        npm ci
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
            post {
                always {
                    publishTestResults testResultsPattern: 'test-results.xml'
                }
            }
        }

        stage('Security Scan') {
            steps {
                container('node') {
                    sh '''
                        npm audit --audit-level=high
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                container('docker') {
                    script {
                        sh '''
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
                    script {
                        withCredentials([aws(credentialsId: 'aws-credentials', region: "${AWS_REGION}")]) {
                            sh '''
                                # Login to ECR
                                aws ecr get-login-password --region ${AWS_REGION} --profile ${AWS_PROFILE} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                                
                                # Tag and push images
                                docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}
                                docker tag ${ECR_REPOSITORY}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:latest
                                
                                docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}
                                docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:latest
                            '''
                        }
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            when {
                branch 'master'
            }
            steps {
                container('kubectl') {
                    script {
                        withCredentials([aws(credentialsId: 'aws-credentials', region: "${AWS_REGION}")]) {
                            sh '''
                                # Update kubeconfig
                                aws eks update-kubeconfig --region ${AWS_REGION} --name demoapp-eks-cluster --profile ${AWS_PROFILE}
                                
                                # Update deployment with new image
                                kubectl set image deployment/demoapp demoapp=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG} -n demoapp
                                
                                # Wait for rollout to complete
                                kubectl rollout status deployment/demoapp -n demoapp --timeout=300s
                                
                                # Verify deployment
                                kubectl get pods -n demoapp
                                kubectl get svc -n demoapp
                                kubectl get ingress -n demoapp
                            '''
                        }
                    }
                }
            }
        }

        stage('Integration Tests') {
            when {
                branch 'master'
            }
            steps {
                container('kubectl') {
                    script {
                        sh '''
                            # Get the ALB endpoint
                            ALB_ENDPOINT=$(kubectl get ingress demoapp-ingress -n demoapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                            
                            # Wait for ALB to be ready
                            echo "Waiting for ALB to be ready..."
                            sleep 60
                            
                            # Test the application endpoint
                            curl -f http://${ALB_ENDPOINT} || exit 1
                            
                            echo "Application is accessible via ALB: ${ALB_ENDPOINT}"
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
            echo 'Pipeline completed successfully!'
            slackSend(
                channel: '#devops',
                color: 'good',
                message: "✅ Pipeline SUCCESS: ${env.JOB_NAME} - ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>)"
            )
        }
        failure {
            echo 'Pipeline failed!'
            slackSend(
                channel: '#devops',
                color: 'danger',
                message: "❌ Pipeline FAILED: ${env.JOB_NAME} - ${env.BUILD_NUMBER} (<${env.BUILD_URL}|Open>)"
            )
        }
    }
} 
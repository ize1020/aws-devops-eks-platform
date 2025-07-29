#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION=${AWS_REGION:-eu-west-1}
AWS_PROFILE=${AWS_PROFILE:-your-profile-name}
CLUSTER_NAME="demoapp-eks-cluster"

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}    AWS EKS Demo Application Deployment    ${NC}"
echo -e "${BLUE}===========================================${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --profile ${AWS_PROFILE} &> /dev/null; then
        print_error "AWS credentials not configured for profile ${AWS_PROFILE}. Please run 'aws configure --profile ${AWS_PROFILE}' first."
        exit 1
    fi
    
    print_status "All prerequisites satisfied!"
}

# Deploy infrastructure
deploy_infrastructure() {
    print_status "Deploying infrastructure with Terraform..."
    
    cd terraform
    
    # Set AWS profile for Terraform
    export AWS_PROFILE=${AWS_PROFILE}
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan -out=tfplan
    
    # Apply deployment
    terraform apply tfplan
    
    # Get outputs
    CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint)
    ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
    
    print_status "Infrastructure deployed successfully!"
    print_status "Cluster Endpoint: ${CLUSTER_ENDPOINT}"
    print_status "ECR Repository: ${ECR_REPOSITORY_URL}"
    
    cd ..
}

# Configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl..."
    
    aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME} --profile ${AWS_PROFILE}
    
    # Test cluster connection
    kubectl cluster-info
    
    print_status "kubectl configured successfully!"
}

# Build and push Docker image
build_and_push_image() {
    print_status "Building and pushing Docker image..."
    
    # Get ECR repository URL
    cd terraform
    ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile ${AWS_PROFILE})
    cd ..
    
    # Login to ECR
    aws ecr get-login-password --region ${AWS_REGION} --profile ${AWS_PROFILE} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    
    # Build image
    docker build -f docker/Dockerfile -t demoapp:latest .
    
    # Tag image
    docker tag demoapp:latest ${ECR_REPOSITORY_URL}:latest
    docker tag demoapp:latest ${ECR_REPOSITORY_URL}:v1.0.0
    
    # Push image
    docker push ${ECR_REPOSITORY_URL}:latest
    docker push ${ECR_REPOSITORY_URL}:v1.0.0
    
    print_status "Docker image built and pushed successfully!"
}

# Deploy application
deploy_application() {
    print_status "Deploying application to Kubernetes..."
    
    # Get ECR repository URL
    cd terraform
    ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile ${AWS_PROFILE})
    cd ..
    
    # Update deployment image (Windows compatible)
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        sed -i "s|image: demoapp:latest|image: ${ECR_REPOSITORY_URL}:latest|g" k8s/deployment.yaml
    else
        sed -i.bak "s|image: demoapp:latest|image: ${ECR_REPOSITORY_URL}:latest|g" k8s/deployment.yaml
    fi
    
    # Apply Kubernetes manifests
    kubectl apply -f k8s/
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/demoapp -n demoapp
    
    print_status "Application deployed successfully!"
}

# Get application URL
get_application_url() {
    print_status "Getting application URL..."
    
    # Wait for ingress to get an address
    print_status "Waiting for Load Balancer to be ready..."
    sleep 60
    
    ALB_HOSTNAME=$(kubectl get ingress demoapp-ingress -n demoapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [ -z "$ALB_HOSTNAME" ]; then
        print_warning "Load Balancer not ready yet. Please check later with:"
        print_warning "kubectl get ingress demoapp-ingress -n demoapp"
    else
        print_status "Application is accessible at: http://${ALB_HOSTNAME}"
        print_status "To use demoapp.com, add this line to your /etc/hosts file:"
        print_status "${ALB_HOSTNAME} demoapp.com"
    fi
}

# Get Jenkins URL
get_jenkins_url() {
    print_status "Getting Jenkins URL..."
    
    JENKINS_LB=$(kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [ -z "$JENKINS_LB" ]; then
        print_warning "Jenkins Load Balancer not ready yet. Please check later with:"
        print_warning "kubectl get svc jenkins -n jenkins"
    else
        print_status "Jenkins is accessible at: http://${JENKINS_LB}:8080"
        print_status "Default credentials: admin / admin123"
    fi
}

# Main deployment function
main() {
    check_prerequisites
    deploy_infrastructure
    configure_kubectl
    build_and_push_image
    deploy_application
    get_application_url
    get_jenkins_url
    
    print_status "Deployment completed successfully!"
    print_status "Next steps:"
    print_status "1. Configure Jenkins pipeline"
    print_status "2. Set up DNS for demoapp.com"
    print_status "3. Configure SSL certificates"
}

# Run main function
main "$@" 

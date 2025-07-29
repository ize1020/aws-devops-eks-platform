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
AWS_PROFILE=${AWS_PROFILE:-rotem-poc}
CLUSTER_NAME="demoapp-eks-cluster"

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}    AWS EKS Infrastructure Cleanup         ${NC}"
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

# Confirmation prompt
confirm_cleanup() {
    print_warning "This will destroy ALL infrastructure including:"
    print_warning "- EKS Cluster"
    print_warning "- VPC and networking components"
    print_warning "- ECR repositories and images"
    print_warning "- Load Balancers"
    print_warning "- All data will be lost!"
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY == "yes" ]]; then
        print_status "Cleanup cancelled."
        exit 0
    fi
}

# Check if kubectl is configured
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        print_warning "kubectl not configured for the cluster. Attempting to configure..."
        aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME} --profile ${AWS_PROFILE} || true
    fi
}

# Clean up Kubernetes resources
cleanup_kubernetes() {
    print_status "Cleaning up Kubernetes resources..."
    
    # Delete application resources
    kubectl delete -f k8s/ --ignore-not-found=true || true
    
    # Delete Jenkins namespace (this will clean up PVCs and PVs)
    kubectl delete namespace jenkins --ignore-not-found=true || true
    
    # Wait for namespace deletion
    print_status "Waiting for namespace deletion..."
    kubectl wait --for=delete namespace/jenkins --timeout=300s || true
    kubectl wait --for=delete namespace/demoapp --timeout=300s || true
    
    print_status "Kubernetes resources cleaned up!"
}

# Clean up Load Balancers manually (if any remain)
cleanup_load_balancers() {
    print_status "Checking for remaining Load Balancers..."
    
    # Get ELBs created by the cluster
    LOAD_BALANCERS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-')].[LoadBalancerArn]" --output text --profile ${AWS_PROFILE} 2>/dev/null || true)
    
    if [ ! -z "$LOAD_BALANCERS" ]; then
        print_status "Found Load Balancers to clean up..."
        for lb in $LOAD_BALANCERS; do
            print_status "Deleting Load Balancer: $lb"
            aws elbv2 delete-load-balancer --load-balancer-arn "$lb" --profile ${AWS_PROFILE} || true
        done
        
        # Wait for deletion
        sleep 30
    fi
}

# Clean up Security Groups
cleanup_security_groups() {
    print_status "Checking for remaining Security Groups..."
    
    # Get VPC ID if it exists
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=demoapp-vpc" --query "Vpcs[0].VpcId" --output text --profile ${AWS_PROFILE} 2>/dev/null || echo "None")
    
    if [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "null" ]; then
        # Get security groups that might block VPC deletion
        SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*k8s*" --query "SecurityGroups[].GroupId" --output text --profile ${AWS_PROFILE} 2>/dev/null || true)
        
        if [ ! -z "$SECURITY_GROUPS" ]; then
            print_status "Found Security Groups to clean up..."
            for sg in $SECURITY_GROUPS; do
                print_status "Deleting Security Group: $sg"
                aws ec2 delete-security-group --group-id "$sg" --profile ${AWS_PROFILE} || true
            done
        fi
    fi
}

# Clean up ECR repositories
cleanup_ecr() {
    print_status "Cleaning up ECR repositories..."
    
    # Force delete ECR repository and all images
    aws ecr delete-repository --repository-name demoapp --force --profile ${AWS_PROFILE} || true
    
    print_status "ECR repositories cleaned up!"
}

# Destroy Terraform infrastructure
destroy_terraform() {
    print_status "Destroying Terraform infrastructure..."
    
    cd terraform
    
    # Initialize Terraform (in case of state issues)
    terraform init
    
    # Destroy infrastructure
    terraform destroy -auto-approve
    
    # Clean up Terraform files
    rm -f terraform.tfstate*
    rm -f tfplan*
    rm -rf .terraform/
    
    cd ..
    
    print_status "Terraform infrastructure destroyed!"
}

# Main cleanup function
main() {
    confirm_cleanup
    check_kubectl
    cleanup_kubernetes
    cleanup_load_balancers
    cleanup_security_groups
    cleanup_ecr
    destroy_terraform
    
    print_status "Cleanup completed successfully!"
    print_status "All infrastructure has been destroyed."
}

# Handle script interruption
trap 'print_error "Cleanup interrupted! You may need to manually clean up remaining resources."; exit 1' INT TERM

# Run main function
main "$@" 
# PowerShell Deployment Script for Windows
param(
    [string]$AwsRegion = "eu-west-1",
    [string]$AwsProfile = "rotem-poc",
    [string]$ClusterName = "demoapp-eks-cluster"
)

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Blue"

Write-Host "===========================================" -ForegroundColor $Blue
Write-Host "    AWS EKS Demo Application Deployment    " -ForegroundColor $Blue
Write-Host "===========================================" -ForegroundColor $Blue

function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $Red
}

function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    try {
        aws --version | Out-Null
    }
    catch {
        Write-Error "AWS CLI is not installed. Please install it first."
        exit 1
    }
    
    # Check if Terraform is installed
    try {
        terraform version | Out-Null
    }
    catch {
        Write-Error "Terraform is not installed. Please install it first."
        exit 1
    }
    
    # Check if kubectl is installed
    try {
        kubectl version --client | Out-Null
    }
    catch {
        Write-Error "kubectl is not installed. Please install it first."
        exit 1
    }
    
    # Check if helm is installed
    try {
        helm version | Out-Null
    }
    catch {
        Write-Error "Helm is not installed. Please install it first."
        exit 1
    }
    
    # Check if Docker is installed
    try {
        docker version | Out-Null
    }
    catch {
        Write-Error "Docker is not installed. Please install it first."
        exit 1
    }
    
    # Check AWS credentials
    try {
        aws sts get-caller-identity --profile $AwsProfile | Out-Null
    }
    catch {
        Write-Error "AWS credentials not configured for profile $AwsProfile. Please run 'aws configure --profile $AwsProfile' first."
        exit 1
    }
    
    Write-Status "All prerequisites satisfied!"
}

function Deploy-Infrastructure {
    Write-Status "Deploying infrastructure with Terraform..."
    
    Set-Location terraform
    
    # Set AWS profile for Terraform
    $env:AWS_PROFILE = $AwsProfile
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan -out=tfplan
    
    # Apply deployment
    terraform apply tfplan
    
    # Get outputs
    $ClusterEndpoint = terraform output -raw cluster_endpoint
    $EcrRepositoryUrl = terraform output -raw ecr_repository_url
    
    Write-Status "Infrastructure deployed successfully!"
    Write-Status "Cluster Endpoint: $ClusterEndpoint"
    Write-Status "ECR Repository: $EcrRepositoryUrl"
    
    Set-Location ..
}

function Set-KubectlConfig {
    Write-Status "Configuring kubectl..."
    
    aws eks update-kubeconfig --region $AwsRegion --name $ClusterName --profile $AwsProfile
    
    # Test cluster connection
    kubectl cluster-info
    
    Write-Status "kubectl configured successfully!"
}

function Build-AndPushImage {
    Write-Status "Building and pushing Docker image..."
    
    # Get ECR repository URL
    Set-Location terraform
    $EcrRepositoryUrl = terraform output -raw ecr_repository_url
    $AwsAccountId = aws sts get-caller-identity --query Account --output text --profile $AwsProfile
    Set-Location ..
    
    # Login to ECR
    $LoginPassword = aws ecr get-login-password --region $AwsRegion --profile $AwsProfile
    $LoginPassword | docker login --username AWS --password-stdin "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"
    
    # Build image
    docker build -f docker/Dockerfile -t demoapp:latest .
    
    # Tag image
    docker tag demoapp:latest "$EcrRepositoryUrl:latest"
    docker tag demoapp:latest "$EcrRepositoryUrl:v1.0.0"
    
    # Push image
    docker push "$EcrRepositoryUrl:latest"
    docker push "$EcrRepositoryUrl:v1.0.0"
    
    Write-Status "Docker image built and pushed successfully!"
}

function Deploy-Application {
    Write-Status "Deploying application to Kubernetes..."
    
    # Get ECR repository URL
    Set-Location terraform
    $EcrRepositoryUrl = terraform output -raw ecr_repository_url
    $AwsAccountId = aws sts get-caller-identity --query Account --output text --profile $AwsProfile
    Set-Location ..
    
    # Update deployment image (PowerShell way)
    $deploymentContent = Get-Content k8s/deployment.yaml -Raw
    $deploymentContent = $deploymentContent -replace '\$\{ECR_REPOSITORY_URL\}', $EcrRepositoryUrl
    Set-Content k8s/deployment.yaml -Value $deploymentContent
    
    # Apply Kubernetes manifests
    kubectl apply -f k8s/
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/demoapp -n demoapp
    
    Write-Status "Application deployed successfully!"
}

function Get-ApplicationUrl {
    Write-Status "Getting application URL..."
    
    # Wait for ingress to get an address
    Write-Status "Waiting for Load Balancer to be ready..."
    Start-Sleep -Seconds 60
    
    $AlbHostname = kubectl get ingress demoapp-ingress -n demoapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
    
    if ([string]::IsNullOrEmpty($AlbHostname)) {
        Write-Warning "Load Balancer not ready yet. Please check later with:"
        Write-Warning "kubectl get ingress demoapp-ingress -n demoapp"
    }
    else {
        Write-Status "Application is accessible at: http://$AlbHostname"
        Write-Status "To use demoapp.com, add this line to your hosts file (C:\Windows\System32\drivers\etc\hosts):"
        Write-Status "$AlbHostname demoapp.com"
    }
}

function Get-JenkinsUrl {
    Write-Status "Getting Jenkins URL..."
    
    $JenkinsLb = kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
    
    if ([string]::IsNullOrEmpty($JenkinsLb)) {
        Write-Warning "Jenkins Load Balancer not ready yet. Please check later with:"
        Write-Warning "kubectl get svc jenkins -n jenkins"
    }
    else {
        Write-Status "Jenkins is accessible at: http://$JenkinsLb:8080"
        Write-Status "Default credentials: admin / admin123"
    }
}

# Main execution
try {
    Test-Prerequisites
    Deploy-Infrastructure
    Set-KubectlConfig
    Build-AndPushImage
    Deploy-Application
    Get-ApplicationUrl
    Get-JenkinsUrl
    
    Write-Status "Deployment completed successfully!"
    Write-Status "Next steps:"
    Write-Status "1. Configure Jenkins pipeline"
    Write-Status "2. Set up DNS for demoapp.com"
    Write-Status "3. Configure SSL certificates"
}
catch {
    Write-Error "Deployment failed: $_"
    exit 1
} 
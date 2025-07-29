# PowerShell Cleanup Script for Windows
param(
    [string]$AwsRegion = "eu-west-1",
    [string]$AwsProfile = "your-profile-name",
    [string]$ClusterName = "demoapp-eks-cluster"
)

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Blue"

Write-Host "===========================================" -ForegroundColor $Blue
Write-Host "    AWS EKS Infrastructure Cleanup         " -ForegroundColor $Blue
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

function Confirm-Cleanup {
    Write-Warning "This will destroy ALL infrastructure including:"
    Write-Warning "- EKS Cluster"
    Write-Warning "- VPC and networking components"
    Write-Warning "- ECR repositories and images"
    Write-Warning "- Load Balancers"
    Write-Warning "- All data will be lost!"
    
    $confirmation = Read-Host "Are you sure you want to continue? (type 'yes' to confirm)"
    if ($confirmation -ne "yes") {
        Write-Status "Cleanup cancelled."
        exit 0
    }
}

function Test-KubectlConfig {
    try {
        kubectl cluster-info | Out-Null
    }
    catch {
        Write-Warning "kubectl not configured for the cluster. Attempting to configure..."
        try {
            aws eks update-kubeconfig --region $AwsRegion --name $ClusterName --profile $AwsProfile
        }
        catch {
            Write-Warning "Could not configure kubectl. Continuing with cleanup..."
        }
    }
}

function Remove-KubernetesResources {
    Write-Status "Cleaning up Kubernetes resources..."
    
    try {
        # Delete application resources
        kubectl delete -f k8s/ --ignore-not-found=true
        
        # Delete Jenkins namespace (this will clean up PVCs and PVs)
        kubectl delete namespace jenkins --ignore-not-found=true
        
        # Wait for namespace deletion
        Write-Status "Waiting for namespace deletion..."
        kubectl wait --for=delete namespace/jenkins --timeout=300s
        kubectl wait --for=delete namespace/demoapp --timeout=300s
        
        Write-Status "Kubernetes resources cleaned up!"
    }
    catch {
        Write-Warning "Some Kubernetes resources may not have been cleaned up: $_"
    }
}

function Remove-LoadBalancers {
    Write-Status "Checking for remaining Load Balancers..."
    
    try {
        # Get ELBs created by the cluster
        $LoadBalancers = aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-')].[LoadBalancerArn]" --output text --profile $AwsProfile 2>$null
        
        if ($LoadBalancers) {
            Write-Status "Found Load Balancers to clean up..."
            $LoadBalancers -split "`n" | ForEach-Object {
                if ($_.Trim()) {
                    Write-Status "Deleting Load Balancer: $_"
                    aws elbv2 delete-load-balancer --load-balancer-arn $_.Trim() --profile $AwsProfile
                }
            }
            
            # Wait for deletion
            Start-Sleep -Seconds 30
        }
    }
    catch {
        Write-Warning "Could not clean up Load Balancers: $_"
    }
}

function Remove-SecurityGroups {
    Write-Status "Checking for remaining Security Groups..."
    
    try {
        # Get VPC ID if it exists
        $VpcId = aws ec2 describe-vpcs --filters "Name=tag:Name,Values=demoapp-vpc" --query "Vpcs[0].VpcId" --output text --profile $AwsProfile 2>$null
        
        if ($VpcId -and $VpcId -ne "None" -and $VpcId -ne "null") {
            # Get security groups that might block VPC deletion
            $SecurityGroups = aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VpcId" "Name=group-name,Values=*k8s*" --query "SecurityGroups[].GroupId" --output text --profile $AwsProfile 2>$null
            
            if ($SecurityGroups) {
                Write-Status "Found Security Groups to clean up..."
                $SecurityGroups -split "`s+" | ForEach-Object {
                    if ($_.Trim()) {
                        Write-Status "Deleting Security Group: $_"
                        aws ec2 delete-security-group --group-id $_.Trim() --profile $AwsProfile
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Could not clean up Security Groups: $_"
    }
}

function Remove-ECRRepositories {
    Write-Status "Cleaning up ECR repositories..."
    
    try {
        # Force delete ECR repository and all images
        aws ecr delete-repository --repository-name demoapp --force --profile $AwsProfile
        
        Write-Status "ECR repositories cleaned up!"
    }
    catch {
        Write-Warning "Could not clean up ECR repository: $_"
    }
}

function Remove-TerraformInfrastructure {
    Write-Status "Destroying Terraform infrastructure..."
    
    try {
        Set-Location terraform
        
        # Initialize Terraform (in case of state issues)
        terraform init
        
        # Destroy infrastructure
        terraform destroy -auto-approve
        
        # Clean up Terraform files
        Remove-Item -Path "terraform.tfstate*" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "tfplan*" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path ".terraform" -Recurse -Force -ErrorAction SilentlyContinue
        
        Set-Location ..
        
        Write-Status "Terraform infrastructure destroyed!"
    }
    catch {
        Write-Error "Failed to destroy Terraform infrastructure: $_"
        Set-Location ..
    }
}

# Main cleanup function
try {
    Confirm-Cleanup
    Test-KubectlConfig
    Remove-KubernetesResources
    Remove-LoadBalancers
    Remove-SecurityGroups
    Remove-ECRRepositories
    Remove-TerraformInfrastructure
    
    Write-Status "Cleanup completed successfully!"
    Write-Status "All infrastructure has been destroyed."
}
catch {
    Write-Error "Cleanup failed: $_"
    exit 1
} 

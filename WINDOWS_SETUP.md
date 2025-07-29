# Windows Setup Guide

This guide provides Windows-specific instructions for setting up and deploying the AWS EKS Demo Application.

## 📋 Prerequisites for Windows

### 1. Install Required Tools

#### AWS CLI v2
```powershell
# Download and install from: https://aws.amazon.com/cli/
# Or using chocolatey:
choco install awscli

# Verify installation
aws --version
```

#### Terraform
```powershell
# Download from: https://www.terraform.io/downloads.html
# Or using chocolatey:
choco install terraform

# Verify installation
terraform version
```

#### kubectl
```powershell
# Download from: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
# Or using chocolatey:
choco install kubernetes-cli

# Verify installation
kubectl version --client
```

#### Helm
```powershell
# Download from: https://helm.sh/docs/intro/install/
# Or using chocolatey:
choco install kubernetes-helm

# Verify installation
helm version
```

#### Docker Desktop
```powershell
# Download and install Docker Desktop from: https://www.docker.com/products/docker-desktop
# Make sure to enable WSL 2 integration if using WSL
```

#### Git for Windows
```powershell
# Download from: https://git-scm.com/download/win
# Or using chocolatey:
choco install git

# Verify installation
git --version
```

### 2. Configure AWS Profile

```powershell
# Configure the rotem-poc profile
aws configure --profile rotem-poc

# You'll be prompted for:
# AWS Access Key ID: [Your Access Key]
# AWS Secret Access Key: [Your Secret Key]
# Default region name: eu-west-1
# Default output format: json

# Verify configuration
aws sts get-caller-identity --profile rotem-poc
```

### 3. Set PowerShell Execution Policy

```powershell
# Run PowerShell as Administrator and execute:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# This allows local scripts to run
```

## 🚀 Deployment

### 1. Clone Repository
```powershell
git clone https://github.com/dandolinsky1/malamhomework.git
cd malamhomework
```

### 2. Deploy Infrastructure
```powershell
# Run the PowerShell deployment script
.\scripts\deploy.ps1
```

### 3. Access Applications

#### Get Application URL
```powershell
$ALB_HOSTNAME = kubectl get ingress demoapp-ingress -n demoapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
Write-Host "Application URL: http://$ALB_HOSTNAME"
```

#### Get Jenkins URL
```powershell
$JENKINS_LB = kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
Write-Host "Jenkins URL: http://$JENKINS_LB:8080"
Write-Host "Credentials: admin / admin123"
```

#### Configure Local DNS (Optional)
```powershell
# Run PowerShell as Administrator
$ALB_HOSTNAME = kubectl get ingress demoapp-ingress -n demoapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "$ALB_HOSTNAME demoapp.com"
```

## 🔧 Troubleshooting

### Docker Issues
- Ensure Docker Desktop is running
- Check WSL 2 integration if using WSL
- Verify Docker daemon is accessible: `docker version`

### PowerShell Issues
- Run PowerShell as Administrator for certain operations
- Check execution policy: `Get-ExecutionPolicy`
- Use PowerShell 7+ for better compatibility

### Path Issues
- Ensure all tools are in your PATH
- Restart PowerShell after installing tools
- Use full paths if needed

### AWS Profile Issues
```powershell
# List all profiles
aws configure list-profiles

# Test specific profile
aws sts get-caller-identity --profile rotem-poc
```

### kubectl Issues
```powershell
# Update kubeconfig
aws eks update-kubeconfig --region eu-west-1 --name demoapp-eks-cluster --profile rotem-poc

# Test connection
kubectl cluster-info
```

## 🧹 Cleanup

### Complete Cleanup
```powershell
# Run the PowerShell cleanup script
.\scripts\cleanup.ps1
```

### Manual Cleanup (if needed)
```powershell
# Delete Kubernetes resources
kubectl delete -f k8s/

# Delete Jenkins
helm uninstall jenkins -n jenkins

# Destroy Terraform infrastructure
cd terraform
terraform destroy -auto-approve
cd ..
```

## 📝 Notes

- Always run PowerShell as Administrator when modifying system files
- Docker Desktop must be running for container operations
- Some antivirus software may interfere with Docker operations
- WSL 2 is recommended for better Docker performance on Windows
- Use PowerShell 7+ for the best experience

## 🔗 Useful Links

- [Docker Desktop for Windows](https://docs.docker.com/desktop/windows/)
- [AWS CLI Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-windows.html)
- [kubectl for Windows](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/)
- [Terraform for Windows](https://learn.hashicorp.com/tutorials/terraform/install-cli)
- [PowerShell 7 Installation](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows) 
# Configure Kubernetes and Helm providers
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.0"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.load_balancer_controller_irsa_role.iam_role_arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [
    module.eks,
    module.load_balancer_controller_irsa_role
  ]
}

# EBS CSI Driver
resource "helm_release" "ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"
  version    = "2.28.1"

  set {
    name  = "controller.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "ebs-csi-controller-sa"
  }

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.ebs_csi_irsa_role.iam_role_arn
  }

  depends_on = [
    module.eks,
    module.ebs_csi_irsa_role
  ]
}

# Jenkins
resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = "jenkins"
  }
  
  depends_on = [module.eks]
}

resource "helm_release" "jenkins" {
  name       = "jenkins"
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  namespace  = "jenkins"
  version    = "5.7.0"

  values = [
    yamlencode({
      controller = {
        admin = {
          password = "admin123"  # Change this in production
        }
        serviceType   = "LoadBalancer"
        serviceAnnotations = {
          "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
        }
        
        installPlugins = [
          "kubernetes:latest",
          "workflow-aggregator:latest",
          "git:latest",
          "configuration-as-code:latest",
          "docker-workflow:latest",
          "blueocean:latest"
        ]
        
        resources = {
          requests = {
            cpu    = "200m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "2000m"
            memory = "2Gi"
          }
        }
        
        javaOpts = "-Djenkins.install.runSetupWizard=false"
        
        JCasC = {
          defaultConfig = true
          configScripts = {
            "welcome-message" = "jenkins:\n  systemMessage: Welcome to our CI/CD server. This Jenkins is configured and managed with Configuration as Code plugin."
          }
        }
      }
      
      agent = {
        enabled = true
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
      
      persistence = {
        enabled      = true
        storageClass = "gp2"
        size         = "8Gi"
      }
    })
  ]

  depends_on = [
    module.eks,
    kubernetes_namespace.jenkins,
    helm_release.ebs_csi_driver
  ]
} 
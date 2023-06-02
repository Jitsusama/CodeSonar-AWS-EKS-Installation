locals {
  vpc_name      = "my-vpc"
  eks_name      = "my-cluster"
  k8s_namespace = "default"
}

# AWS ALB Configuration
locals {
  alb_region = "us-east-2"
  # WARNING: change below if value above is not us-east-2
  alb_image_repository = "602401143452.dkr.ecr.us-east-2.amazonaws.com/amazon/aws-load-balancer-controller"
}

# OCI Image Registry Configuration
locals {
  image_registry_uri      = "https://docker.hub"
  image_registry_user     = "username"
  image_registry_password = "password"
}

# Helm Repository Configuration
locals {
  helm_repository_uri      = "https://helm.repo"
  helm_repository_user     = "username"
  helm_repository_password = "password"
}

# CodeSonar Image Configuration
locals {
  codesonar_launchd_image = "docker.hub/grammatech/codesonar-launchd:7.3p1"
  codesonar_hub_image     = "docker.hub/grammatech/codesonar-hub:7.3p1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.47"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.8"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10"
    }
  }
  required_version = "~> 1.0"
}

// Use AWS CLI credentials.
provider "aws" {}

// Use in-cluster config or local configuration.
provider "kubernetes" {}

// Use in-cluster config or local configuration.
provider "helm" {}

data "aws_availability_zones" "current_region" {}

# Docs: https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/3.19.0
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.vpc_name
  azs  = slice(data.aws_availability_zones.current_region.names, 0, 2)

  # Configure IP subnetting.
  cidr            = "10.0.0.0/16"
  private_subnets = ["10.0.0.0/19", "10.0.32.0/19"]
  public_subnets  = ["10.0.64.0/19", "10.0.96.0/19"]
  intra_subnets   = ["10.0.128.0/19", "10.0.160.0/19"]

  # Enable routing to the outside internet via a NAT gateway.
  enable_nat_gateway = true
  single_nat_gateway = true

  # Allow DNS names to be mapped to resources attached to this VPC.
  enable_dns_hostnames = true

  # Logs all traffic across ENI interfaces attached to this VPC.
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  # These tags prepare us to support the Amazon Load Balancer Controller.
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.eks_name}" = "shared"
    "kubernetes.io/role/elb"                  = 1
  }

  # These tags prepare us to support the Amazon Load Balancer Controller.
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.eks_name}" = "shared"
    "kubernetes.io/role/internal-elb"         = 1
  }
}

# Docs: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/19.5.1
module "k8s" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.eks_name
  cluster_version = "1.26"

  # Allow cluster creation/deletion/modification to take a while.
  cluster_timeouts = {
    create = "120m"
    update = "120m"
    delete = "120m"
  }

  # Configure cluster networking.
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # Enable logging for all internal Kubernetes resources.
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Allow outside world access to the Kubernetes API.
  cluster_endpoint_public_access = true

  # Linux Node Groups
  eks_managed_node_groups = {
    # Amazon Linux 2, 4 AMD vCPUs, 16 GiB RAM, 5Gi Network
    "linux-workers" = {
      ami_type = "AL2_x86_64"
      ami_release_version = jsondecode(
        data.aws_ssm_parameter.latest_cluster_eks_linux.value
      ).release_version
      instance_types             = ["t3a.xlarge"]
      use_custom_launch_template = false
      min_size                   = 2
      desired_size               = 2
      max_size                   = 10
      disk_size                  = "500"
    }
  }
}

# Grabs the latest recommended AMI release for Linux worker nodes on our cluster.
data "aws_ssm_parameter" "latest_cluster_eks_linux" {
  name = "/aws/service/eks/optimized-ami/1.26/amazon-linux-2/recommended"
}

# Default service account for the namespace.
resource "kubernetes_default_service_account_v1" "default_sa" {
  metadata {
    namespace = local.k8s_namespace
  }
  image_pull_secret {
    name = "image-pull-secret"
  }
}

# KOCHsource image pull secret.
resource "kubernetes_secret_v1" "image_pull_secret" {
  metadata {
    name      = "image-pull-secret"
    namespace = local.k8s_namespace
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        local.registry_uri = {
          auth = base64encode("${local.image_registry_user}:${local.image_registry_password}")
        }
      }
    })
  }
}

# AWS ALB Controller
# Docs: https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller
resource "helm_release" "ingress_alb_controller" {
  name       = "aws-ingress-alb-controller"
  namespace  = local.k8s_namespace
  chart      = "aws-load-balancer-controller"
  version    = "1.4.7"
  repository = "https://aws.github.io/eks-charts"

  values = [
    yamlencode({
      fullnameOverride = "aws-ingress-alb-controller"
      clusterName      = module.k8s.cluster_name
      image = {
        repository = local.alb_image_repository
      }
      nodeSelector = {
        "kubernetes.io/os" = "linux"
      }
      serviceAccount = {
        name = "aws-ingress-alb-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.ingress_alb_controller.arn
        }
      }
    })
  ]
}

# IRSA role for the ingress ALB controller.
resource "aws_iam_role" "ingress_alb_controller" {
  name        = "aws-ingress-alb-controller"
  description = "This role should be used by AWS ALB controllers."

  managed_policy_arns = [aws_iam_policy.ingress_alb_controller.arn]
  assume_role_policy = jsonencode({
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = module.k8s.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${module.k8s.oidc_provider}:sub" = "system:serviceaccount:${local.k8s_namespace}:aws-ingress-alb-controller"
            "${module.k8s.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
    Version = "2012-10-17"
  })
}

# Allows an ingress ALB controller to CRUD ALB configuration.
# Docs: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/deploy/installation/#option-a-iam-roles-for-service-accounts-irsa
resource "aws_iam_policy" "ingress_alb_controller" {
  name        = "aws-ingress-alb-controller-alb-updates"
  description = "Allows an AWS ingress ALB controller to CRUD ALB configuration."
  policy      = file("${path.module}/ingress_alb_controller.json")
}

# AWS EBS CSI Driver
# Docs: https://github.com/kubernetes-sigs/aws-ebs-csi-driver/tree/master/charts/aws-ebs-csi-driver
resource "helm_release" "aws_ebs_csi_driver" {
  name      = "aws-ebs-csi"
  namespace = local.k8s_namespace

  chart      = "aws-ebs-csi-driver"
  version    = "2.16.0"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"

  values = [
    yamlencode({
      controller = {
        region = local.alb_region
        nodeSelector = {
          "kubernetes.io/os" = "linux"
        }
        serviceAccount = {
          name = "aws-ebs-csi-controller"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.aws_ebs_csi_controller.arn
          }
        }
      }
      node = {
        nodeSelector = {
          "kubernetes.io/os" = "linux"
        }
      }
      storageClasses = [
        {
          name = "ebs-default"
          annotations = {
            "storageclass.kubernetes.io/is-default-class" = "true"
          }
          volumeBindingMode = "WaitForFirstConsumer"
          reclaimPolicy     = "Delete"
          parameters = {
            encrypted                   = "true"
            type                        = "gp3"
            "csi.storage.k8s.io/fstype" = "ext4"
          }
        },
      ]
    })
  ]
}

# IRSA role for the AWS EBS CSI controller.
# Docs: https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
resource "aws_iam_role" "aws_ebs_csi_controller" {
  name        = "aws-ebs-csi-controller"
  description = "This role should be used by EBS CSI controllers."

  # FYI: This one is created and managed by Amazon.
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
  assume_role_policy = jsonencode({
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = module.k8s.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${module.k8s.oidc_provider}:sub" = "system:serviceaccount:${local.k8s_namespace}:aws-ebs-csi-controller"
            "${module.k8s.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
    Version = "2012-10-17"
  })
}

variable "CODESONAR_ADMIN_PASSWORD" {
  type        = string
  sensitive   = true
  description = "Administrative password for CodeSonar hubs."
}

# The CodeSonar Hub.
resource "helm_release" "codesonar" {
  name      = "codesonar"
  namespace = local.k8s_namespace

  chart               = "CodeSonar"
  version             = "1.0.0"
  repository          = local.helm_repository_uri
  repository_username = local.helm_repository_user
  repository_password = local.helm_repository_password

  values = [
    yamlencode({
      launchd = {
        image   = local.codesonar_launchd_image
        cpu     = "1"  # vCPUs
        ram     = "8"  # Gi of RAM
        storage = "64" # gigs of storage for project files
      }
      hub = {
        image    = local.codesonar_hub_image
        port     = "7340"
        password = var.CODESONAR_ADMIN_PASSWORD
        cpu      = "2"  # vCPUs
        ram      = "8"  # Gi of RAM
        storage  = "64" # gigs of storage for project files
      }
    })
  ]
}

resource "kubernetes_ingress_v1" "codesonar" {
  metadata {
    name      = "codesonar-hub"
    namespace = local.k8s_namespace
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }])
      "alb.ingress.kubernetes.io/healthcheck-port" = "7340"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
      "alb.ingress.kubernetes.io/success-codes"    = "200,403"
    }
  }
  spec {
    rule {
      http {
        path {
          path_type = "Prefix"
          path      = "/"
          backend {
            service {
              name = "codesonar-hub"
              port {
                number = 7340
              }
            }
          }
        }
      }
    }
  }
}

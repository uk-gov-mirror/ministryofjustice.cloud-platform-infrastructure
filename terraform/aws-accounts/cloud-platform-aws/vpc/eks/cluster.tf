###############
# EKS Cluster #
###############


data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "v12.2.0"

  cluster_name     = local.cluster_name
  subnets          = concat(tolist(data.aws_subnet_ids.private.ids), tolist(data.aws_subnet_ids.public.ids))
  vpc_id           = data.aws_vpc.selected.id
  write_kubeconfig = false
  cluster_version  = "1.17"
  enable_irsa      = true

  node_groups = {
    default_ng = {
      desired_capacity = var.cluster_node_count
      max_capacity     = 30
      min_capacity     = 1
      subnets          = data.aws_subnet_ids.private.ids

      instance_type = var.worker_node_machine_type
      k8s_labels = {
        Terraform = "true"
        Cluster   = local.cluster_name
        Domain    = local.cluster_base_domain_name
      }
      additional_tags = {
        default_ng = "true"
      }
    }
  }

  # Out of the box you can't specify groups to map, just users. Some people did some workarounds
  # we can explore later: https://ygrene.tech/mapping-iam-groups-to-eks-user-access-66fd745a6b77
  map_users = [
    {
      userarn  = "arn:aws:iam::754256621582:user/AlejandroGarrido"
      username = "AlejandroGarrido"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::754256621582:user/PoornimaKrishnasamy"
      username = "PoornimaKrishnasamy"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::754256621582:user/paulWyborn"
      username = "paulWyborn"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::754256621582:user/SabluMiah"
      username = "SabluMiah"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::754256621582:user/jasonBirchall"
      username = "jasonBirchall"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::754256621582:user/RazvanCosma"
      username = "RazvanCosma"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::754256621582:user/cloud-platform/manager-concourse"
      username = "manager-concourse"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::754256621582:user/SteveMarshall"
      username = "SteveMarshall"
      groups   = ["system:masters"]
    }


  ]

  tags = {
    Terraform = "true"
    Cluster   = local.cluster_name
    Domain    = local.cluster_base_domain_name
  }
}

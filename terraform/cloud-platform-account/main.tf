terraform {
  required_version = ">= 0.12"
  backend "s3" {
    bucket         = "cloud-platform-terraform-state"
    region         = "eu-west-1"
    key            = "cloud-platform-account/terraform.tfstate"
    profile        = "moj-cp"
    dynamodb_table = "cloud-platform-terraform-state"
  }
}

provider "aws" {
  region  = "eu-west-2"
  profile = "moj-cp"
}

# Because we are managining kops state in Ireland
provider "aws" {
  alias   = "ireland"
  region  = "eu-west-1"
  profile = "moj-cp"
}

# IAM configuration for cloud-platform. Users, groups, etc
module "iam" {
  source = "github.com/ministryofjustice/cloud-platform-terraform-awsaccounts-iam?ref=0.0.6"

  aws_account_name = "cloud-platform-aws"
}

# Baselines: cloudtrail, cloudwatch, lambda. Everything that our accounts should have
module "baselines" {
  source = "github.com/ministryofjustice/cloud-platform-terraform-awsaccounts-baselines?ref=0.0.7"

  enable_logging           = true
  enable_slack_integration = true

  region        = var.aws_region
  slack_webhook = var.slack_config_cloudwatch_lp
  slack_channel = "lower-priority-alarms"

  s3_bucket_block_publicaccess_exceptions = [
    "cloud-platform-9025c5a1a81bca7eaefd78a38df7d7de",
    "cloud-platform-fdc5e4b70a599d8ea84b4ffd31a832b3",
    "cloud-platform-6cf3132ef8fce52bb371b1d02f40c36d",
    "cloud-platform-dfc64bcd6ed89a72777fc7924f9da01e",
  ]
}

# Route53 hostzone
resource "aws_route53_zone" "cloud_platform_justice_gov_uk" {
  name = "cloud-platform.service.justice.gov.uk."
}

module "ecr_fluentbit" {
  source = "github.com/ministryofjustice/cloud-platform-terraform-ecr-credentials?ref=4.5"

  repo_name = "fluent-bit"
  team_name = "cloud-platform"
}


##############
# S3 buckets #
##############

module "s3_bucket_thanos" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "1.18.0"

  bucket = "cloud-platform-prometheus-thanos"
  acl    = "private"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = false
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

}

module "s3_bucket_velero" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "1.18.0"

  bucket = "cloud-platform-velero-backups"
  acl    = "private"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

}

##############
# KOps state #
##############

resource "aws_s3_bucket" "cloud_platform_kops_state" {
  bucket   = "cloud-platform-kops-state"
  provider = aws.ireland
  acl      = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  replication_configuration {
    role = aws_iam_role.s3_replication_kops_state.arn
    rules {
      status = "Enabled"
      destination {
        bucket = aws_s3_bucket.cloud_platform_kops_state_replica.arn
      }
    }
  }
  lifecycle {
    ignore_changes = [
      replication_configuration[0].rules,
    ]
  }
}

resource "aws_s3_bucket" "cloud_platform_kops_state_replica" {
  bucket = "cloud-platform-kops-state-replica"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "kops_state_replica" {
  bucket = "cloud-platform-kops-state-replica"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [
    aws_s3_bucket.cloud_platform_kops_state_replica,
  ]
}

resource "aws_iam_role" "s3_replication_kops_state" {
  name        = "s3_role_cloud_platform_kops_state"
  description = "Allow S3 to assume the role for replication"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "s3ReplicationAssume",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "s3_replication_kops_state" {
  name        = "s3_cloud_platform_kops_state"
  description = "Allows reading for replication."

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "s3:Get*",
                "s3:ListBucket"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::cloud-platform-kops-state",
                "arn:aws:s3:::cloud-platform-kops-state/*"
            ]
        },
        {
            "Action": [
                "s3:ReplicateObject",
                "s3:ReplicateDelete",
                "s3:ReplicateTags",
                "s3:GetObjectVersionTagging"
            ],
            "Effect": "Allow",
            "Resource": "arn:aws:s3:::cloud-platform-kops-state-replica/*"
        }
    ]
}
POLICY
}

resource "aws_iam_policy_attachment" "s3_replication_kops_state" {
  name       = "s3_cloud_platform_kops_state_attachment"
  roles      = [aws_iam_role.s3_replication_kops_state.name]
  policy_arn = aws_iam_policy.s3_replication_kops_state.arn
}


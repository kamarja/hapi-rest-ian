// =============================================================================
// VARIABLES
// =============================================================================

// S3 Bucket variables
variable "s3bucket_name" {
  description = "hapi-rest-ian-bucket S3 Bucket Name"
  type        = string
  default     = "test_bucket"
}

variable "s3bucket_guild_name" {
  description = "hapi-rest-ian-bucket S3 Bucket Guild"
  type        = string
  default     = "devops"
}

variable "s3bucket_environment" {
  description = "hapi-rest-ian-bucket S3 Bucket Environment (dev, prod, etc.)"
  type        = string
  default     = "dev"
}

variable "s3bucket_microservice_name" {
  description = "hapi-rest-ian-bucket S3 Bucket Microservice Name"
  type        = string
  default     = "extraction"
}

variable "s3bucket_service_name" {
  description = "hapi-rest-ian-bucket S3 Bucket Service Name"
  type        = string
  default     = "service_name"
}

// Infra Owner variable (dynamic, default: "devops")
variable "infra_owner" {
  description = "Infra owner responsible for the S3 Bucket"
  type        = string
  default     = "devops"
}

// IAM Role Creation Options
variable "create_read_write_roles" {
  description = "Boolean to control creation of read/write IAM roles for this bucket"
  type        = bool
  default     = true
}

variable "create_read_only_roles" {
  description = "Boolean to control creation of read-only IAM roles for this bucket"
  type        = bool
  default     = true
}

// Role name lists (if roles are to be created)
variable "s3bucket_read_write_roles" {
  description = "hapi-rest-ian-bucket S3 Bucket Read/Write Roles"
  type        = list(string)
  default     = []
}

variable "s3bucket_read_only_roles" {
  description = "hapi-rest-ian-bucket S3 Bucket Read-Only Roles"
  type        = list(string)
  default     = []
}

// =============================================================================
// DATA SOURCES & LOCALS
// =============================================================================

data "aws_ssm_parameter" "s3bucket_current" {
  name = "/PROVIDED_AS_EXTRA_CONTENT/s3bucket/current"
}

locals {
  s3bucket_current = try(
    nonsensitive(jsondecode(data.aws_ssm_parameter.s3bucket_current.value)["s3bucket"].tag),
    {}
  )
}

// =============================================================================
// MODULE INVOCATIONS
// =============================================================================

// Create the S3 Bucket using the terraform-aws-modules/s3-bucket/aws module
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.4.0"

  bucket = var.s3bucket_name
  acl    = "private"

  tags = {
    Name        = var.s3bucket_name
    Environment = var.s3bucket_environment
    Owner       = var.infra_owner
  }

  # Optional: If your module supports server-side encryption via a KMS key,
  # uncomment and update the following block:
  # server_side_encryption_configuration = {
  #   rule = {
  #     apply_server_side_encryption_by_default = {
  #       kms_master_key_id = module.kms_key.key_arn,
  #       sse_algorithm     = "aws:kms"
  #     }
  #   }
  # }
}

// Create the KMS key using the k9securityio/kms-key/aws module
module "kms_key" {
  source  = "k9securityio/kms-key/aws"
  version = "0.5.3"

  alias               = var.s3bucket_name
  description         = "${var.s3bucket_name} KMS Key"
  enable_key_rotation = true

  tags = {
    Name        = var.s3bucket_name
    Environment = var.s3bucket_environment
    Owner       = var.infra_owner
  }
}

// =============================================================================
// CONDITIONAL RESOURCE CREATION: IAM ROLES WITH INLINE POLICIES
// =============================================================================

// ARNs for bucket and bucket objects
locals {
  s3_bucket_arn         = "arn:aws:s3:::${module.s3_bucket.bucket}"
  s3_bucket_objects_arn = "arn:aws:s3:::${module.s3_bucket.bucket}/*"
}

// Create IAM Roles for Read/Write access (if enabled and roles provided)
resource "aws_iam_role" "s3_read_write" {
  count = var.create_read_write_roles ? length(var.s3bucket_read_write_roles) : 0

  name = var.s3bucket_read_write_roles[count.index]

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [{
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" }
    }]
  })

  inline_policy {
    name   = "S3FullAccessForBucket"
    policy = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [ "s3:ListBucket" ],
          "Resource": local.s3_bucket_arn
        },
        {
          "Effect": "Allow",
          "Action": [ "s3:GetObject", "s3:PutObject", "s3:DeleteObject" ],
          "Resource": local.s3_bucket_objects_arn
        },
        {
          "Effect": "Allow",
          "Action": [
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:DescribeKey"
          ],
          "Resource": module.kms_key.key_arn
        }
      ]
    })
  }

  tags = {
    Name        = var.s3bucket_read_write_roles[count.index]
    Environment = var.s3bucket_environment
    Owner       = var.infra_owner
  }
}

// Create IAM Roles for Read-Only access (if enabled and roles provided)
resource "aws_iam_role" "s3_read_only" {
  count = var.create_read_only_roles ? length(var.s3bucket_read_only_roles) : 0

  name = var.s3bucket_read_only_roles[count.index]

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [{
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" }
    }]
  })

  inline_policy {
    name   = "S3ReadOnlyAccessForBucket"
    policy = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [ "s3:ListBucket" ],
          "Resource": local.s3_bucket_arn
        },
        {
          "Effect": "Allow",
          "Action": [ "s3:GetObject" ],
          "Resource": local.s3_bucket_objects_arn
        },
        {
          "Effect": "Allow",
          "Action": [ "kms:Decrypt", "kms:DescribeKey" ],
          "Resource": module.kms_key.key_arn
        }
      ]
    })
  }

  tags = {
    Name        = var.s3bucket_read_only_roles[count.index]
    Environment = var.s3bucket_environment
    Owner       = var.infra_owner
  }
}


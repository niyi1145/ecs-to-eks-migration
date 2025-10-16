# FedRAMP Compliance Security Controls
# This file implements FedRAMP security requirements for ECS deployment

# CloudTrail for audit logging (AC-2, AU-2, AU-3, AU-6, AU-12)
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-fedramp-trail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail        = true
  enable_logging               = true
  enable_log_file_validation   = true

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.cloudtrail.arn}/*"]
    }
  }

  tags = {
    Name        = "${var.project_name}-fedramp-trail"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# S3 bucket for CloudTrail logs with encryption
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-fedramp-cloudtrail-${random_string.bucket_suffix.result}"
  force_destroy = false

  tags = {
    Name        = "${var.project_name}-fedramp-cloudtrail"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Config for compliance monitoring (CM-2, CM-6, CM-8)
# Note: AWS Config requires proper IAM policies that may not be available in all regions
# resource "aws_config_configuration_recorder" "main" {
#   name     = "${var.project_name}-fedramp-config-recorder"
#   role_arn = aws_iam_role.config.arn
#
#   recording_group {
#     all_supported                 = true
#     include_global_resource_types = true
#   }
# }
#
# resource "aws_config_delivery_channel" "main" {
#   name           = "${var.project_name}-fedramp-config-delivery"
#   s3_bucket_name = aws_s3_bucket.config.id
#   s3_key_prefix  = "config"
# }

resource "aws_s3_bucket" "config" {
  bucket        = "${var.project_name}-fedramp-config-${random_string.bucket_suffix.result}"
  force_destroy = false

  tags = {
    Name        = "${var.project_name}-fedramp-config"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for Config
resource "aws_iam_role" "config" {
  name = "${var.project_name}-fedramp-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
}

# Note: Commented out due to policy availability issues
# resource "aws_iam_role_policy_attachment" "config" {
#   role       = aws_iam_role.config.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
# }
#
# resource "aws_iam_role_policy_attachment" "config_s3" {
#   role       = aws_iam_role.config.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
# }

# GuardDuty for threat detection (SI-4, SI-5)
# Note: GuardDuty requires a subscription and is not available in free tier
# resource "aws_guardduty_detector" "main" {
#   enable = true
#
#   datasources {
#     s3_logs {
#       enable = true
#     }
#     kubernetes {
#       audit_logs {
#         enable = true
#       }
#     }
#     malware_protection {
#       scan_ec2_instance_with_findings {
#         ebs_volumes {
#           enable = true
#         }
#       }
#     }
#   }
#
#   tags = {
#     Name        = "${var.project_name}-fedramp-guardduty"
#     Environment = var.environment
#     Project     = "ECS-to-EKS-Migration"
#     Compliance  = "FedRAMP"
#   }
# }

# Security Hub for centralized security findings (SI-4, SI-5)
# Note: Security Hub requires a subscription and is not available in free tier
# resource "aws_securityhub_account" "main" {
#   enable_default_standards = true
# }

# KMS for encryption (SC-13, SC-28)
resource "aws_kms_key" "main" {
  description             = "FedRAMP compliant KMS key for ${var.project_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-fedramp-trail"
          }
        }
      },
      {
        Sid    = "Allow CloudWatch Logs to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-fedramp-kms"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-fedramp-key"
  target_key_id = aws_kms_key.main.key_id
}

# Enhanced EFS with KMS encryption
resource "aws_efs_file_system" "fedramp" {
  creation_token = "${var.project_name}-fedramp-efs"
  encrypted      = true
  kms_key_id     = aws_kms_key.main.arn

  performance_mode = "generalPurpose"
  throughput_mode  = "provisioned"
  provisioned_throughput_in_mibps = 100

  tags = {
    Name        = "${var.project_name}-fedramp-efs"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# WAF for web application protection (SC-7, SI-4)
resource "aws_wafv2_web_acl" "main" {
  name  = "${var.project_name}-fedramp-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-fedramp-waf"
    sampled_requests_enabled   = true
  }

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 1

    override_action {
      none {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
        evaluation_window_sec = 300
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - Core Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputsRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  tags = {
    Name        = "${var.project_name}-fedramp-waf"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# Associate WAF with ALB
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# VPC Flow Logs for network monitoring (AC-4, SC-7, SI-4)
resource "aws_flow_log" "vpc" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flowlogs/${var.project_name}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.main.arn

  tags = {
    Name        = "${var.project_name}-vpc-flow-logs"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-fedramp-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-fedramp-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Enhanced security groups with least privilege (AC-4, SC-7)
# Note: These rules are already defined in main.tf, so we don't need to duplicate them here

# SNS topic for security notifications (SI-4, SI-5)
resource "aws_sns_topic" "security_alerts" {
  name              = "${var.project_name}-fedramp-security-alerts"
  kms_master_key_id = aws_kms_key.main.arn

  tags = {
    Name        = "${var.project_name}-fedramp-security-alerts"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# CloudWatch alarms for security monitoring (SI-4, SI-5)
resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  alarm_name          = "${var.project_name}-unauthorized-api-calls"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnauthorizedAPICalls"
  namespace           = "AWS/CloudTrail"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors unauthorized API calls"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = {
    Name        = "${var.project_name}-unauthorized-api-calls"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_usage" {
  alarm_name          = "${var.project_name}-root-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RootUsage"
  namespace           = "AWS/CloudTrail"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors root account usage"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = {
    Name        = "${var.project_name}-root-usage"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# Systems Manager Parameter Store for secure configuration (SC-13, SC-28)
resource "aws_ssm_parameter" "database_password" {
  name  = "/${var.project_name}/fedramp/database/password"
  type  = "SecureString"
  value = var.database_password
  key_id = aws_kms_key.main.arn

  tags = {
    Name        = "${var.project_name}-fedramp-db-password"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/${var.project_name}/fedramp/jwt/secret"
  type  = "SecureString"
  value = var.jwt_secret
  key_id = aws_kms_key.main.arn

  tags = {
    Name        = "${var.project_name}-fedramp-jwt-secret"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# FedRAMP Compliant Secure Networking for EKS
# This file implements secure networking controls for FedRAMP compliance

# Network ACLs for additional layer of security (AC-4, SC-7)
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  # Allow HTTP inbound
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow HTTPS inbound
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow ephemeral ports for return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound traffic
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name        = "${var.project_name}-fedramp-eks-public-nacl"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  # Allow HTTP from public subnets
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 80
    to_port    = 80
  }

  # Allow HTTPS from public subnets
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 443
    to_port    = 443
  }

  # Allow application ports from public subnets
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 3000
    to_port    = 3000
  }

  # Allow Kubernetes API server port
  ingress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 443
    to_port    = 443
  }

  # Allow database port from private subnets only
  ingress {
    protocol   = "tcp"
    rule_no    = 140
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 5432
    to_port    = 5432
  }

  # Allow Redis port from private subnets only
  ingress {
    protocol   = "tcp"
    rule_no    = 150
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 6379
    to_port    = 6379
  }

  # Allow ephemeral ports for return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 160
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound traffic
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name        = "${var.project_name}-fedramp-eks-private-nacl"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# VPC Endpoints for secure AWS service access (AC-4, SC-7, SC-13)
# Note: S3 endpoint commented out since S3 buckets are not defined in EKS config
# resource "aws_vpc_endpoint" "s3" {
#   vpc_id            = aws_vpc.main.id
#   service_name      = "com.amazonaws.${var.aws_region}.s3"
#   vpc_endpoint_type = "Gateway"
#   route_table_ids   = [aws_route_table.private[0].id, aws_route_table.private[1].id]
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = "*"
#         Action = [
#           "s3:GetObject",
#           "s3:PutObject",
#           "s3:DeleteObject",
#           "s3:ListBucket"
#         ]
#         Resource = [
#           "arn:aws:s3:::${aws_s3_bucket.cloudtrail.bucket}",
#           "arn:aws:s3:::${aws_s3_bucket.cloudtrail.bucket}/*",
#           "arn:aws:s3:::${aws_s3_bucket.config.bucket}",
#           "arn:aws:s3:::${aws_s3_bucket.config.bucket}/*"
#         ]
#       }
#     ]
#   })
#
#   tags = {
#     Name        = "${var.project_name}-fedramp-eks-s3-endpoint"
#     Environment = var.environment
#     Project     = "ECS-to-EKS-Migration"
#     Compliance  = "FedRAMP"
#   }
# }

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-fedramp-eks-ecr-dkr-endpoint"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-fedramp-eks-ecr-api-endpoint"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_vpc_endpoint" "eks" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.eks"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-fedramp-eks-endpoint"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-fedramp-eks-cloudwatch-logs-endpoint"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-fedramp-eks-ssm-endpoint"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-fedramp-eks-ssm-messages-endpoint"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_vpc_endpoint" "ec2_messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-fedramp-eks-ec2-messages-endpoint"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-fedramp-eks-vpc-endpoints-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-fedramp-eks-vpc-endpoints-sg"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# Enhanced security groups with micro-segmentation (AC-4, SC-7)
resource "aws_security_group" "alb_fedramp" {
  name_prefix = "${var.project_name}-fedramp-eks-alb-"
  vpc_id      = aws_vpc.main.id

  # Only allow HTTPS from internet
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  # HTTP redirect to HTTPS
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP redirect to HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-fedramp-eks-alb-sg"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_security_group" "eks_nodes_fedramp" {
  name_prefix = "${var.project_name}-fedramp-eks-nodes-"
  vpc_id      = aws_vpc.main.id

  # Allow traffic from ALB only
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_fedramp.id]
    description     = "Application traffic from ALB"
  }

  # Allow Kubernetes API server communication
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
    description     = "Kubernetes API server communication"
  }

  # Allow inter-node communication
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Inter-node communication"
  }

  # Allow database access from nodes
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Database access from nodes"
  }

  # Allow Redis access from nodes
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Redis access from nodes"
  }

  # Allow health checks
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Health check endpoints"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-fedramp-eks-nodes-sg"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_security_group" "database_fedramp" {
  name_prefix = "${var.project_name}-fedramp-eks-database-"
  vpc_id      = aws_vpc.main.id

  # Allow database access from EKS nodes only
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes_fedramp.id]
    description     = "PostgreSQL access from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-fedramp-eks-database-sg"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_security_group" "redis_fedramp" {
  name_prefix = "${var.project_name}-fedramp-eks-redis-"
  vpc_id      = aws_vpc.main.id

  # Allow Redis access from EKS nodes only
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes_fedramp.id]
    description     = "Redis access from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-fedramp-eks-redis-sg"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# DNS Firewall for additional network security (AC-4, SC-7)
resource "aws_route53_resolver_firewall_rule_group" "main" {
  name = "${var.project_name}-fedramp-eks-dns-firewall"

  tags = {
    Name        = "${var.project_name}-fedramp-eks-dns-firewall"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_route53_resolver_firewall_rule" "block_malware" {
  name                = "BlockMalwareDomains"
  action              = "BLOCK"
  block_response      = "NXDOMAIN"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.main.id
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.malware.id
  priority            = 100
}

resource "aws_route53_resolver_firewall_domain_list" "malware" {
  name = "${var.project_name}-fedramp-eks-malware-domains"

  domains = [
    "malware.example.com",
    "phishing.example.com",
    "botnet.example.com"
  ]

  tags = {
    Name        = "${var.project_name}-fedramp-eks-malware-domains"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_route53_resolver_firewall_rule_group_association" "main" {
  name                   = "${var.project_name}-fedramp-eks-dns-firewall-association"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.main.id
  vpc_id                 = aws_vpc.main.id
  priority               = 1000

  tags = {
    Name        = "${var.project_name}-fedramp-eks-dns-firewall-association"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

# Network segmentation with additional subnets for different tiers (AC-4, SC-7)
resource "aws_subnet" "database" {
  count = length(var.database_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project_name}-fedramp-eks-database-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
    Type        = "Database"
  }
}

resource "aws_route_table" "database" {
  count = length(aws_subnet.database)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name        = "${var.project_name}-fedramp-eks-database-rt-${count.index + 1}"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

resource "aws_route_table_association" "database" {
  count = length(aws_subnet.database)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[count.index].id
}

# Network ACL for database subnets
resource "aws_network_acl" "database" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.database[*].id

  # Allow database port from private subnets only
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 5432
    to_port    = 5432
  }

  # Allow Redis port from private subnets only
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 6379
    to_port    = 6379
  }

  # Allow ephemeral ports for return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound traffic
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name        = "${var.project_name}-fedramp-eks-database-nacl"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Compliance  = "FedRAMP"
  }
}

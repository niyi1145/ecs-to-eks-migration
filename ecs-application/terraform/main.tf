terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Type        = "Public"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
    Type        = "Private"
  }
}

# NAT Gateway
resource "aws_eip" "nat" {
  count = length(aws_subnet.public)

  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-nat-eip-${count.index + 1}"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = length(aws_subnet.public)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "${var.project_name}-nat-gateway-${count.index + 1}"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_route_table" "private" {
  count = length(aws_subnet.private)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name        = "${var.project_name}-private-rt-${count.index + 1}"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.project_name}-ecs-tasks-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-ecs-tasks-sg"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_security_group" "database" {
  name_prefix = "${var.project_name}-database-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-database-sg"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-cluster"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# Target Groups
resource "aws_lb_target_group" "frontend" {
  name        = "${var.project_name}-frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-frontend-tg"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_lb_target_group" "backend" {
  name        = "${var.project_name}-backend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-backend-tg"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# Load Balancer Listeners
resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener" "backend" {
  load_balancer_arn = aws_lb.main.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# EFS File System
resource "aws_efs_file_system" "main" {
  creation_token = "${var.project_name}-efs"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "provisioned"
  provisioned_throughput_in_mibps = 100

  tags = {
    Name        = "${var.project_name}-efs"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# EFS Mount Targets
resource "aws_efs_mount_target" "main" {
  count = length(aws_subnet.private)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.ecs_tasks.id]
}

# EFS Access Point
resource "aws_efs_access_point" "main" {
  file_system_id = aws_efs_file_system.main.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/data"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name        = "${var.project_name}-efs-access-point"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ecs" {
  for_each = toset(["todo-backend", "todo-frontend", "todo-database", "todo-redis"])

  name              = "/ecs/${each.key}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-${each.key}-logs"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# Service Discovery Namespace
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.project_name}.local"
  description = "Service discovery namespace for ${var.project_name}"
  vpc         = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-service-discovery"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# Service Discovery Services
resource "aws_service_discovery_service" "backend" {
  name = "todo-backend"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }


  tags = {
    Name        = "${var.project_name}-backend-discovery"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_service_discovery_service" "frontend" {
  name = "todo-frontend"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  tags = {
    Name        = "${var.project_name}-frontend-discovery"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_service_discovery_service" "database" {
  name = "todo-database"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  tags = {
    Name        = "${var.project_name}-database-discovery"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_service_discovery_service" "redis" {
  name = "todo-redis"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }


  tags = {
    Name        = "${var.project_name}-redis-discovery"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# ECS IAM Roles
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ecs-task-execution-role"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ecs-task-role"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# ECS Task Definitions
resource "aws_ecs_task_definition" "backend" {
  family                   = "todo-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

         container_definitions = jsonencode([
           {
             name  = "todo-backend"
             image = "public.ecr.aws/nginx/nginx:alpine"
             portMappings = [
               {
                 containerPort = 80
                 protocol      = "tcp"
               }
             ]
      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "DATABASE_URL"
          value = "postgresql://todo:${var.db_password}@database.${var.project_name}.local:5432/todo"
        },
        {
          name  = "REDIS_URL"
          value = "redis://redis.${var.project_name}.local:6379"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/todo-backend"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-backend-task"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "todo-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

         container_definitions = jsonencode([
           {
             name  = "todo-frontend"
             image = "public.ecr.aws/nginx/nginx:alpine"
             portMappings = [
               {
                 containerPort = 80
                 protocol      = "tcp"
               }
             ]
      environment = [
        {
          name  = "REACT_APP_API_URL"
          value = "http://backend.${var.project_name}.local:80"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/todo-frontend"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-frontend-task"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_ecs_task_definition" "database" {
  family                   = "todo-database"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

         container_definitions = jsonencode([
           {
             name  = "todo-database"
             image = "public.ecr.aws/docker/library/postgres:13"
      portMappings = [
        {
          containerPort = 5432
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "POSTGRES_DB"
          value = "todo"
        },
        {
          name  = "POSTGRES_USER"
          value = "todo"
        },
        {
          name  = "POSTGRES_PASSWORD"
          value = var.db_password
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/todo-database"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-database-task"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_ecs_task_definition" "redis" {
  family                   = "todo-redis"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

         container_definitions = jsonencode([
           {
             name  = "todo-redis"
             image = "public.ecr.aws/docker/library/redis:6-alpine"
      portMappings = [
        {
          containerPort = 6379
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/todo-redis"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-redis-task"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

# ECS Services
resource "aws_ecs_service" "backend" {
  name            = "todo-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.backend.arn
  }

  depends_on = [aws_lb_listener.frontend]

  tags = {
    Name        = "${var.project_name}-backend-service"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_ecs_service" "frontend" {
  name            = "todo-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "todo-frontend"
    container_port   = 80
  }

  service_registries {
    registry_arn = aws_service_discovery_service.frontend.arn
  }

  depends_on = [aws_lb_listener.frontend]

  tags = {
    Name        = "${var.project_name}-frontend-service"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_ecs_service" "database" {
  name            = "todo-database"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.database.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.database[*].id
    security_groups  = [aws_security_group.database.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.database.arn
  }

  tags = {
    Name        = "${var.project_name}-database-service"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

resource "aws_ecs_service" "redis" {
  name            = "todo-redis"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.redis.arn
  }

  tags = {
    Name        = "${var.project_name}-redis-service"
    Environment = var.environment
    Project     = "ECS-to-EKS-Migration"
  }
}

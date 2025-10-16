# ECS to EKS Migration Guide

## 🎯 Overview

This guide provides a comprehensive step-by-step process for migrating a microservices application from **Amazon ECS (Elastic Container Service)** to **Amazon EKS (Elastic Kubernetes Service)**. We'll use a Todo application as our example, but the principles apply to any containerized application.

## 📋 Prerequisites

### Required Tools
- **AWS CLI** v2.0+
- **kubectl** v1.21+
- **Docker** v20.10+
- **Python** v3.8+
- **Terraform** v1.0+ (optional)
- **Helm** v3.0+ (optional)

### AWS Permissions
- ECS cluster access
- EKS cluster access
- ECR repository access
- IAM role management
- VPC and networking access

### Knowledge Requirements
- Basic understanding of ECS concepts
- Basic understanding of Kubernetes concepts
- Docker containerization
- AWS services (ECR, VPC, IAM)

## 🏗️ Architecture Comparison

### ECS Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                        AWS ECS                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Frontend  │  │   Backend   │  │   Database  │         │
│  │   Service   │  │   Service   │  │   Service   │         │
│  │             │  │             │  │             │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                 │                 │              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Task      │  │   Task      │  │   Task      │         │
│  │ Definition  │  │ Definition  │  │ Definition  │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                 │                 │              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Service   │  │   Service   │  │   Service   │         │
│  │             │  │             │  │             │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                 │                 │              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Cluster   │  │   Cluster   │  │   Cluster   │         │
│  │             │  │             │  │             │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

### EKS Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                        AWS EKS                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                    Control Plane                        │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │
│  │  │   API       │  │   etcd      │  │  Scheduler  │     │ │
│  │  │   Server    │  │             │  │             │     │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘     │ │
│  └─────────────────────────────────────────────────────────┘ │
│                              │                              │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                   Worker Nodes                          │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │
│  │  │   Frontend  │  │   Backend   │  │   Database  │     │ │
│  │  │     Pod     │  │     Pod     │  │     Pod     │     │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘     │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │ │
│  │  │   Service   │  │   Service   │  │   Service   │     │ │
│  │  │             │  │             │  │             │     │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘     │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 🔄 Migration Process

### Phase 1: Preparation

#### 1.1 Assess Current ECS Setup
```bash
# List ECS clusters
aws ecs list-clusters

# Describe cluster
aws ecs describe-clusters --clusters your-cluster-name

# List services
aws ecs list-services --cluster your-cluster-name

# List task definitions
aws ecs list-task-definitions
```

#### 1.2 Create EKS Cluster
```bash
# Create EKS cluster using eksctl
eksctl create cluster \
  --name todo-cluster \
  --region us-east-1 \
  --nodegroup-name workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 5 \
  --managed

# Or using Terraform (see terraform/eks-cluster.tf)
```

#### 1.3 Set Up ECR Repositories
```bash
# Create ECR repositories
aws ecr create-repository --repository-name todo-backend
aws ecr create-repository --repository-name todo-frontend

# Get login token
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
```

### Phase 2: Application Migration

#### 2.1 Build and Push Images
```bash
# Build backend image
cd ecs-application/backend
docker build -t todo-backend:latest .
docker tag todo-backend:latest ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/todo-backend:latest
docker push ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/todo-backend:latest

# Build frontend image
cd ../frontend
docker build -t todo-frontend:latest .
docker tag todo-frontend:latest ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/todo-frontend:latest
docker push ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/todo-frontend:latest
```

#### 2.2 Convert ECS to Kubernetes Manifests
```bash
# Run the conversion script
python3 migration-scripts/ecs-to-k8s/ecs-to-k8s-converter.py \
  --input ecs-application \
  --output migration-output \
  --namespace todo-app \
  --registry ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
```

#### 2.3 Deploy to EKS
```bash
# Create namespace
kubectl create namespace todo-app

# Apply manifests
kubectl apply -f eks-application/manifests/ -n todo-app
kubectl apply -f migration-output/ -n todo-app

# Check deployment status
kubectl get pods -n todo-app
kubectl get services -n todo-app
```

### Phase 3: Data Migration

#### 3.1 Database Migration
```bash
# Create migration configuration
cat > source-config.json << EOF
{
  "database": {
    "host": "ecs-database-endpoint",
    "port": 5432,
    "database": "todoapp",
    "user": "postgres",
    "password": "password"
  },
  "redis": {
    "host": "ecs-redis-endpoint",
    "port": 6379
  }
}
EOF

cat > target-config.json << EOF
{
  "database": {
    "host": "todo-database-service.todo-app.svc.cluster.local",
    "port": 5432,
    "database": "todoapp",
    "user": "postgres",
    "password": "password"
  },
  "redis": {
    "host": "todo-redis-service.todo-app.svc.cluster.local",
    "port": 6379
  }
}
EOF

# Run data migration
python3 migration-scripts/data-migration/data-migration.py \
  --source-config source-config.json \
  --target-config target-config.json
```

#### 3.2 Validate Data Migration
```bash
# Check database connectivity
kubectl port-forward service/todo-database-service 5432:5432 -n todo-app
psql -h localhost -p 5432 -U postgres -d todoapp -c "SELECT COUNT(*) FROM users;"

# Check Redis connectivity
kubectl port-forward service/todo-redis-service 6379:6379 -n todo-app
redis-cli -h localhost -p 6379 ping
```

### Phase 4: Testing and Validation

#### 4.1 Run Validation Script
```bash
# Create validation configuration
cat > validation-config.json << EOF
{
  "namespace": "todo-app",
  "services": {
    "backend": "todo-backend-service",
    "frontend": "todo-frontend-service",
    "database": "todo-database-service",
    "redis": "todo-redis-service"
  }
}
EOF

# Run validation
python3 migration-scripts/validation/validate-migration.py \
  --config validation-config.json \
  --namespace todo-app
```

#### 4.2 Manual Testing
```bash
# Port forward to backend
kubectl port-forward service/todo-backend-service 3000:3000 -n todo-app

# Test API endpoints
curl http://localhost:3000/health
curl http://localhost:3000/api/auth/register -X POST -H "Content-Type: application/json" -d '{"username":"test","email":"test@example.com","password":"password123"}'

# Port forward to frontend
kubectl port-forward service/todo-frontend-service 3001:3000 -n todo-app

# Test frontend
curl http://localhost:3001/health
```

### Phase 5: DNS and Load Balancer Setup

#### 5.1 Configure Ingress
```bash
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml

# Apply ingress configuration
kubectl apply -f eks-application/manifests/ingress/ingress.yaml -n todo-app

# Get ingress endpoint
kubectl get ingress -n todo-app
```

#### 5.2 Update DNS Records
```bash
# Get load balancer endpoint
INGRESS_ENDPOINT=$(kubectl get ingress todo-app-ingress -n todo-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Update DNS records to point to the new endpoint
# This depends on your DNS provider (Route 53, Cloudflare, etc.)
```

### Phase 6: Monitoring and Observability

#### 6.1 Set Up Prometheus and Grafana
```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Install Grafana
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set persistence.enabled=true \
  --set adminPassword=admin
```

#### 6.2 Configure Logging
```bash
# Install Fluentd
kubectl apply -f https://raw.githubusercontent.com/fluent/fluentd-kubernetes-daemonset/master/fluentd-daemonset-elasticsearch.yaml

# Configure log aggregation (CloudWatch, ELK, etc.)
```

### Phase 7: Cleanup

#### 7.1 ECS Resource Cleanup
```bash
# Stop ECS services
aws ecs update-service --cluster your-cluster-name --service todo-backend-service --desired-count 0
aws ecs update-service --cluster your-cluster-name --service todo-frontend-service --desired-count 0
aws ecs update-service --cluster your-cluster-name --service todo-database-service --desired-count 0
aws ecs update-service --cluster your-cluster-name --service todo-redis-service --desired-count 0

# Delete ECS services
aws ecs delete-service --cluster your-cluster-name --service todo-backend-service
aws ecs delete-service --cluster your-cluster-name --service todo-frontend-service
aws ecs delete-service --cluster your-cluster-name --service todo-database-service
aws ecs delete-service --cluster your-cluster-name --service todo-redis-service

# Delete ECS cluster
aws ecs delete-cluster --cluster your-cluster-name
```

## 🚨 Common Issues and Solutions

### Issue 1: Image Pull Errors
**Problem**: Pods stuck in `ImagePullBackOff` state
**Solution**:
```bash
# Check image repository permissions
aws ecr describe-repositories --repository-names todo-backend

# Verify image exists
aws ecr describe-images --repository-name todo-backend

# Check ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
```

### Issue 2: Database Connection Issues
**Problem**: Backend can't connect to database
**Solution**:
```bash
# Check database service
kubectl get service todo-database-service -n todo-app

# Check database pod logs
kubectl logs -f deployment/todo-database -n todo-app

# Test database connectivity
kubectl port-forward service/todo-database-service 5432:5432 -n todo-app
psql -h localhost -p 5432 -U postgres -d todoapp
```

### Issue 3: Redis Connection Issues
**Problem**: Backend can't connect to Redis
**Solution**:
```bash
# Check Redis service
kubectl get service todo-redis-service -n todo-app

# Check Redis pod logs
kubectl logs -f deployment/todo-redis -n todo-app

# Test Redis connectivity
kubectl port-forward service/todo-redis-service 6379:6379 -n todo-app
redis-cli -h localhost -p 6379 ping
```

### Issue 4: Ingress Not Working
**Problem**: External traffic not reaching services
**Solution**:
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress status
kubectl describe ingress todo-app-ingress -n todo-app

# Check load balancer
kubectl get service -n ingress-nginx
```

## 📊 Performance Comparison

### ECS vs EKS Performance Metrics

| Metric | ECS | EKS |
|--------|-----|-----|
| **Startup Time** | 30-60s | 45-90s |
| **Resource Overhead** | 5-10% | 10-15% |
| **Scaling Speed** | 30-60s | 60-120s |
| **Networking** | AWS VPC | CNI Plugin |
| **Storage** | EFS/EFS | Persistent Volumes |
| **Load Balancing** | ALB/NLB | Ingress Controller |

### Cost Comparison

| Component | ECS Cost | EKS Cost |
|-----------|----------|----------|
| **Control Plane** | $0 | $0.10/hour |
| **Worker Nodes** | EC2 pricing | EC2 pricing |
| **Load Balancer** | ALB pricing | ALB pricing |
| **Storage** | EFS pricing | EBS pricing |
| **Networking** | VPC pricing | VPC pricing |

## 🔧 Best Practices

### 1. Resource Management
- Use resource requests and limits
- Implement horizontal pod autoscaling
- Monitor resource usage

### 2. Security
- Use non-root containers
- Implement network policies
- Use secrets management
- Enable RBAC

### 3. Monitoring
- Set up comprehensive logging
- Implement health checks
- Use Prometheus for metrics
- Set up alerting

### 4. Backup and Recovery
- Regular database backups
- Persistent volume snapshots
- Disaster recovery planning

## 📚 Additional Resources

- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Docker Documentation](https://docs.docker.com/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)

## 🎉 Conclusion

Migrating from ECS to EKS is a complex process that requires careful planning and execution. This guide provides a comprehensive approach to ensure a successful migration while minimizing downtime and maintaining application functionality.

Remember to:
- Test thoroughly in a staging environment
- Have a rollback plan ready
- Monitor the application closely during and after migration
- Document any custom configurations or workarounds

Good luck with your migration! 🚀

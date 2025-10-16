#!/bin/bash

# ECS to EKS Migration Script
# This script automates the migration process from ECS to EKS

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ECS_DIR="$PROJECT_DIR/ecs-application"
EKS_DIR="$PROJECT_DIR/eks-application"
MIGRATION_DIR="$PROJECT_DIR/migration-scripts"
OUTPUT_DIR="$PROJECT_DIR/migration-output"

# AWS Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
CLUSTER_NAME="${CLUSTER_NAME:-todo-cluster}"
NAMESPACE="${NAMESPACE:-todo-app}"

# ECR Configuration
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if required tools are installed
    local tools=("aws" "kubectl" "docker" "python3" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check kubectl context
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl is not configured or cluster is not accessible."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

setup_environment() {
    log_info "Setting up migration environment..."
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
    fi
    
    log_success "Environment setup complete"
}

build_and_push_images() {
    log_info "Building and pushing Docker images..."
    
    local services=("backend" "frontend")
    
    for service in "${services[@]}"; do
        log_info "Building $service image..."
        
        # Build image
        docker build -t "$service:latest" "$ECS_DIR/$service/"
        
        # Tag for ECR
        docker tag "$service:latest" "$ECR_REGISTRY/$service:latest"
        
        # Push to ECR
        log_info "Pushing $service image to ECR..."
        aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
        docker push "$ECR_REGISTRY/$service:latest"
        
        log_success "$service image pushed successfully"
    done
}

convert_ecs_to_k8s() {
    log_info "Converting ECS definitions to Kubernetes manifests..."
    
    # Run the Python converter
    python3 "$MIGRATION_DIR/ecs-to-k8s/ecs-to-k8s-converter.py" \
        --input "$ECS_DIR" \
        --output "$OUTPUT_DIR" \
        --namespace "$NAMESPACE" \
        --registry "$ECR_REGISTRY"
    
    log_success "ECS to Kubernetes conversion complete"
}

deploy_to_eks() {
    log_info "Deploying to EKS cluster..."
    
    # Apply all manifests
    local manifest_dirs=("$EKS_DIR/manifests" "$OUTPUT_DIR")
    
    for dir in "${manifest_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_info "Applying manifests from $dir..."
            kubectl apply -f "$dir" --namespace="$NAMESPACE"
        fi
    done
    
    # Wait for deployments to be ready
    log_info "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment --all -n "$NAMESPACE"
    
    log_success "Deployment to EKS complete"
}

validate_deployment() {
    log_info "Validating deployment..."
    
    # Check pod status
    log_info "Checking pod status..."
    kubectl get pods -n "$NAMESPACE"
    
    # Check service status
    log_info "Checking service status..."
    kubectl get services -n "$NAMESPACE"
    
    # Check ingress status
    log_info "Checking ingress status..."
    kubectl get ingress -n "$NAMESPACE"
    
    # Run health checks
    log_info "Running health checks..."
    local services=("todo-backend" "todo-frontend" "todo-database" "todo-redis")
    
    for service in "${services[@]}"; do
        if kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
            local ready_replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
            local desired_replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
            
            if [ "$ready_replicas" = "$desired_replicas" ]; then
                log_success "$service is ready ($ready_replicas/$desired_replicas)"
            else
                log_warning "$service is not ready ($ready_replicas/$desired_replicas)"
            fi
        fi
    done
}

generate_migration_report() {
    log_info "Generating migration report..."
    
    local report_file="$OUTPUT_DIR/migration-report.md"
    
    cat > "$report_file" << EOF
# ECS to EKS Migration Report

## Migration Summary
- **Date**: $(date)
- **Source**: ECS Cluster
- **Target**: EKS Cluster ($CLUSTER_NAME)
- **Namespace**: $NAMESPACE
- **Registry**: $ECR_REGISTRY

## Services Migrated
EOF
    
    # List migrated services
    kubectl get deployments -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | while read -r service; do
        echo "- $service" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Migration Status
- [x] Prerequisites check
- [x] Environment setup
- [x] Image build and push
- [x] ECS to Kubernetes conversion
- [x] EKS deployment
- [x] Validation

## Next Steps
1. Update DNS records to point to EKS ingress
2. Monitor application performance
3. Set up monitoring and alerting
4. Plan ECS resource cleanup

## Useful Commands
\`\`\`bash
# Check pod status
kubectl get pods -n $NAMESPACE

# Check service status
kubectl get services -n $NAMESPACE

# Check ingress status
kubectl get ingress -n $NAMESPACE

# View logs
kubectl logs -f deployment/todo-backend -n $NAMESPACE

# Port forward for testing
kubectl port-forward service/todo-backend-service 3000:3000 -n $NAMESPACE
\`\`\`
EOF
    
    log_success "Migration report generated: $report_file"
}

cleanup_ecs() {
    log_warning "This will delete ECS resources. Are you sure? (y/N)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log_info "Cleaning up ECS resources..."
        
        # Stop ECS services
        local services=("todo-backend-service" "todo-frontend-service" "todo-database-service" "todo-redis-service")
        for service in "${services[@]}"; do
            if aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$service" &> /dev/null; then
                log_info "Stopping ECS service: $service"
                aws ecs update-service --cluster "$CLUSTER_NAME" --service "$service" --desired-count 0
            fi
        done
        
        log_success "ECS cleanup initiated"
    else
        log_info "ECS cleanup skipped"
    fi
}

show_help() {
    cat << EOF
ECS to EKS Migration Script

Usage: $0 [OPTIONS]

Options:
    --help, -h          Show this help message
    --build-only        Only build and push images
    --convert-only      Only convert ECS to Kubernetes manifests
    --deploy-only       Only deploy to EKS
    --validate-only     Only validate deployment
    --cleanup-ecs       Clean up ECS resources after migration
    --skip-build        Skip image build and push
    --skip-convert      Skip ECS to Kubernetes conversion
    --skip-deploy       Skip EKS deployment
    --skip-validate     Skip deployment validation

Environment Variables:
    AWS_REGION          AWS region (default: us-east-1)
    AWS_ACCOUNT_ID      AWS account ID (auto-detected)
    CLUSTER_NAME        EKS cluster name (default: todo-cluster)
    NAMESPACE           Kubernetes namespace (default: todo-app)

Examples:
    $0                  # Full migration
    $0 --build-only     # Only build and push images
    $0 --deploy-only    # Only deploy to EKS
    $0 --cleanup-ecs    # Full migration with ECS cleanup
EOF
}

# Main execution
main() {
    local build_only=false
    local convert_only=false
    local deploy_only=false
    local validate_only=false
    local cleanup_ecs=false
    local skip_build=false
    local skip_convert=false
    local skip_deploy=false
    local skip_validate=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --build-only)
                build_only=true
                shift
                ;;
            --convert-only)
                convert_only=true
                shift
                ;;
            --deploy-only)
                deploy_only=true
                shift
                ;;
            --validate-only)
                validate_only=true
                shift
                ;;
            --cleanup-ecs)
                cleanup_ecs=true
                shift
                ;;
            --skip-build)
                skip_build=true
                shift
                ;;
            --skip-convert)
                skip_convert=true
                shift
                ;;
            --skip-deploy)
                skip_deploy=true
                shift
                ;;
            --skip-validate)
                skip_validate=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Execute based on options
    if [ "$build_only" = true ]; then
        check_prerequisites
        build_and_push_images
    elif [ "$convert_only" = true ]; then
        convert_ecs_to_k8s
    elif [ "$deploy_only" = true ]; then
        check_prerequisites
        setup_environment
        deploy_to_eks
    elif [ "$validate_only" = true ]; then
        validate_deployment
    else
        # Full migration
        check_prerequisites
        setup_environment
        
        if [ "$skip_build" = false ]; then
            build_and_push_images
        fi
        
        if [ "$skip_convert" = false ]; then
            convert_ecs_to_k8s
        fi
        
        if [ "$skip_deploy" = false ]; then
            deploy_to_eks
        fi
        
        if [ "$skip_validate" = false ]; then
            validate_deployment
        fi
        
        generate_migration_report
        
        if [ "$cleanup_ecs" = true ]; then
            cleanup_ecs
        fi
    fi
    
    log_success "Migration process completed!"
}

# Run main function
main "$@"

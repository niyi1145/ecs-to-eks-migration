# ECS to EKS Migration Troubleshooting Guide

## 🚨 Common Issues and Solutions

This guide covers the most common issues encountered during ECS to EKS migration and provides step-by-step solutions.

## 📋 Table of Contents

1. [Prerequisites Issues](#prerequisites-issues)
2. [Image and Container Issues](#image-and-container-issues)
3. [Networking Issues](#networking-issues)
4. [Database Issues](#database-issues)
5. [Redis Issues](#redis-issues)
6. [Ingress and Load Balancer Issues](#ingress-and-load-balancer-issues)
7. [Security and RBAC Issues](#security-and-rbac-issues)
8. [Monitoring and Logging Issues](#monitoring-and-logging-issues)
9. [Performance Issues](#performance-issues)
10. [Data Migration Issues](#data-migration-issues)

## 🔧 Prerequisites Issues

### Issue 1: AWS CLI Not Configured

**Problem**: `aws: command not found` or `Unable to locate credentials`

**Solution**:
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS CLI
aws configure
# Enter your Access Key ID, Secret Access Key, region, and output format

# Verify configuration
aws sts get-caller-identity
```

### Issue 2: kubectl Not Installed

**Problem**: `kubectl: command not found`

**Solution**:
```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verify installation
kubectl version --client
```

### Issue 3: EKS Cluster Not Accessible

**Problem**: `error: You must be logged in to the server (Unauthorized)`

**Solution**:
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name your-cluster-name

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

## 🐳 Image and Container Issues

### Issue 1: ImagePullBackOff

**Problem**: Pods stuck in `ImagePullBackOff` state

**Symptoms**:
```
NAME                     READY   STATUS             RESTARTS   AGE
todo-backend-xxx         0/1     ImagePullBackOff   0          5m
```

**Solution**:
```bash
# Check pod details
kubectl describe pod todo-backend-xxx -n todo-app

# Check image repository
aws ecr describe-repositories --repository-names todo-backend

# Verify image exists
aws ecr describe-images --repository-name todo-backend

# Check ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Rebuild and push image
docker build -t todo-backend:latest .
docker tag todo-backend:latest ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/todo-backend:latest
docker push ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/todo-backend:latest
```

### Issue 2: Container CrashLoopBackOff

**Problem**: Pods in `CrashLoopBackOff` state

**Symptoms**:
```
NAME                     READY   STATUS                 RESTARTS   AGE
todo-backend-xxx         0/1     CrashLoopBackOff       5          10m
```

**Solution**:
```bash
# Check pod logs
kubectl logs todo-backend-xxx -n todo-app

# Check pod events
kubectl describe pod todo-backend-xxx -n todo-app

# Check resource limits
kubectl get pod todo-backend-xxx -n todo-app -o yaml | grep -A 10 resources

# Common fixes:
# 1. Increase memory limits
# 2. Fix environment variables
# 3. Check health check endpoints
# 4. Verify database connectivity
```

### Issue 3: Init Container Failures

**Problem**: Init containers failing to start

**Solution**:
```bash
# Check init container logs
kubectl logs todo-backend-xxx -c init-container -n todo-app

# Check init container status
kubectl describe pod todo-backend-xxx -n todo-app

# Common fixes:
# 1. Check init container image
# 2. Verify init container permissions
# 3. Check init container resources
```

## 🌐 Networking Issues

### Issue 1: Services Not Accessible

**Problem**: Services not reachable from other pods

**Symptoms**:
```
# From inside a pod
curl: (7) Failed to connect to todo-backend-service:3000: Connection refused
```

**Solution**:
```bash
# Check service endpoints
kubectl get endpoints todo-backend-service -n todo-app

# Check service selector
kubectl get service todo-backend-service -n todo-app -o yaml

# Check pod labels
kubectl get pods -n todo-app --show-labels

# Verify service DNS
kubectl run test-pod --image=busybox --rm -it -- nslookup todo-backend-service.todo-app.svc.cluster.local
```

### Issue 2: Network Policies Blocking Traffic

**Problem**: Network policies preventing pod communication

**Solution**:
```bash
# Check network policies
kubectl get networkpolicies -n todo-app

# Describe network policy
kubectl describe networkpolicy todo-app-network-policy -n todo-app

# Temporarily disable network policy for testing
kubectl delete networkpolicy todo-app-network-policy -n todo-app

# Test connectivity
kubectl run test-pod --image=busybox --rm -it -- wget -qO- http://todo-backend-service:3000/health
```

### Issue 3: DNS Resolution Issues

**Problem**: Pods can't resolve service names

**Solution**:
```bash
# Check DNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check DNS service
kubectl get service kube-dns -n kube-system

# Test DNS resolution
kubectl run test-pod --image=busybox --rm -it -- nslookup kubernetes.default

# Check CoreDNS configuration
kubectl get configmap coredns -n kube-system -o yaml
```

## 🗄️ Database Issues

### Issue 1: Database Connection Refused

**Problem**: Backend can't connect to database

**Symptoms**:
```
Error: connect ECONNREFUSED 127.0.0.1:5432
```

**Solution**:
```bash
# Check database service
kubectl get service todo-database-service -n todo-app

# Check database pod
kubectl get pods -l app=todo-database -n todo-app

# Check database logs
kubectl logs -l app=todo-database -n todo-app

# Test database connectivity
kubectl port-forward service/todo-database-service 5432:5432 -n todo-app
psql -h localhost -p 5432 -U postgres -d todoapp

# Check database environment variables
kubectl exec -it todo-backend-xxx -n todo-app -- env | grep DB_
```

### Issue 2: Database Authentication Failed

**Problem**: Database authentication errors

**Solution**:
```bash
# Check database secrets
kubectl get secret todo-database-secrets -n todo-app -o yaml

# Verify secret values
kubectl get secret todo-database-secrets -n todo-app -o jsonpath='{.data.postgres-password}' | base64 -d

# Check database user
kubectl exec -it todo-database-xxx -n todo-app -- psql -U postgres -c "\du"

# Reset database password
kubectl exec -it todo-database-xxx -n todo-app -- psql -U postgres -c "ALTER USER postgres PASSWORD 'newpassword';"
```

### Issue 3: Database Schema Issues

**Problem**: Database tables not created

**Solution**:
```bash
# Check database logs for schema creation
kubectl logs -l app=todo-database -n todo-app | grep -i "create table"

# Manually create tables
kubectl exec -it todo-database-xxx -n todo-app -- psql -U postgres -d todoapp -c "
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"

# Check existing tables
kubectl exec -it todo-database-xxx -n todo-app -- psql -U postgres -d todoapp -c "\dt"
```

## 🔴 Redis Issues

### Issue 1: Redis Connection Refused

**Problem**: Backend can't connect to Redis

**Solution**:
```bash
# Check Redis service
kubectl get service todo-redis-service -n todo-app

# Check Redis pod
kubectl get pods -l app=todo-redis -n todo-app

# Check Redis logs
kubectl logs -l app=todo-redis -n todo-app

# Test Redis connectivity
kubectl port-forward service/todo-redis-service 6379:6379 -n todo-app
redis-cli -h localhost -p 6379 ping

# Check Redis environment variables
kubectl exec -it todo-backend-xxx -n todo-app -- env | grep REDIS_
```

### Issue 2: Redis Memory Issues

**Problem**: Redis running out of memory

**Solution**:
```bash
# Check Redis memory usage
kubectl exec -it todo-redis-xxx -n todo-app -- redis-cli info memory

# Check Redis configuration
kubectl exec -it todo-redis-xxx -n todo-app -- redis-cli config get maxmemory

# Update Redis configuration
kubectl exec -it todo-redis-xxx -n todo-app -- redis-cli config set maxmemory 256mb
kubectl exec -it todo-redis-xxx -n todo-app -- redis-cli config set maxmemory-policy allkeys-lru

# Check Redis keys
kubectl exec -it todo-redis-xxx -n todo-app -- redis-cli keys "*"
```

## 🌍 Ingress and Load Balancer Issues

### Issue 1: Ingress Not Working

**Problem**: External traffic not reaching services

**Solution**:
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check ingress status
kubectl describe ingress todo-app-ingress -n todo-app

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Check load balancer
kubectl get service -n ingress-nginx

# Test ingress endpoint
curl -H "Host: todo-app.example.com" http://INGRESS_IP/health
```

### Issue 2: SSL/TLS Issues

**Problem**: HTTPS not working

**Solution**:
```bash
# Check TLS secret
kubectl get secret todo-app-tls -n todo-app

# Check cert-manager
kubectl get pods -n cert-manager

# Check certificate status
kubectl describe certificate todo-app-tls -n todo-app

# Check certificate issuer
kubectl get clusterissuer letsencrypt-prod
```

### Issue 3: Load Balancer Not Created

**Problem**: Load balancer not provisioned

**Solution**:
```bash
# Check ingress controller service
kubectl get service -n ingress-nginx

# Check AWS load balancer controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check AWS load balancer controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check IAM permissions
aws iam get-role --role-name AmazonEKSLoadBalancerControllerRole
```

## 🔐 Security and RBAC Issues

### Issue 1: Pod Security Context Issues

**Problem**: Pods failing due to security context

**Solution**:
```bash
# Check pod security context
kubectl get pod todo-backend-xxx -n todo-app -o yaml | grep -A 10 securityContext

# Check pod security policies
kubectl get psp

# Check pod security standards
kubectl get pod todo-backend-xxx -n todo-app -o yaml | grep -A 5 securityContext

# Common fixes:
# 1. Set runAsNonRoot: true
# 2. Set runAsUser: 1001
# 3. Set readOnlyRootFilesystem: true
# 4. Add securityContext to pod spec
```

### Issue 2: RBAC Permission Issues

**Problem**: Service accounts lacking permissions

**Solution**:
```bash
# Check service account
kubectl get serviceaccount todo-backend-sa -n todo-app

# Check role binding
kubectl get rolebinding -n todo-app

# Check cluster role binding
kubectl get clusterrolebinding | grep todo-backend

# Create role and role binding
kubectl create role todo-backend-role --verb=get,list,watch --resource=pods -n todo-app
kubectl create rolebinding todo-backend-rolebinding --role=todo-backend-role --serviceaccount=todo-app:todo-backend-sa -n todo-app
```

### Issue 3: Network Policy Issues

**Problem**: Network policies blocking traffic

**Solution**:
```bash
# Check network policies
kubectl get networkpolicies -n todo-app

# Describe network policy
kubectl describe networkpolicy todo-app-network-policy -n todo-app

# Test without network policy
kubectl delete networkpolicy todo-app-network-policy -n todo-app

# Test connectivity
kubectl run test-pod --image=busybox --rm -it -- wget -qO- http://todo-backend-service:3000/health

# Recreate network policy with correct rules
kubectl apply -f network-policy.yaml
```

## 📊 Monitoring and Logging Issues

### Issue 1: Prometheus Not Scraping Metrics

**Problem**: Metrics not appearing in Prometheus

**Solution**:
```bash
# Check Prometheus pods
kubectl get pods -n monitoring -l app=prometheus

# Check Prometheus configuration
kubectl get configmap prometheus-server -n monitoring -o yaml

# Check service monitors
kubectl get servicemonitor -n todo-app

# Check Prometheus targets
kubectl port-forward service/prometheus-server 9090:80 -n monitoring
# Open http://localhost:9090/targets in browser
```

### Issue 2: Grafana Not Accessible

**Problem**: Can't access Grafana dashboard

**Solution**:
```bash
# Check Grafana pods
kubectl get pods -n monitoring -l app=grafana

# Check Grafana service
kubectl get service grafana -n monitoring

# Port forward to Grafana
kubectl port-forward service/grafana 3000:80 -n monitoring

# Check Grafana logs
kubectl logs -l app=grafana -n monitoring

# Get Grafana admin password
kubectl get secret grafana-admin -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```

### Issue 3: Logs Not Appearing

**Problem**: Application logs not visible

**Solution**:
```bash
# Check pod logs
kubectl logs -l app=todo-backend -n todo-app

# Check log aggregation
kubectl get pods -n kube-system -l k8s-app=fluentd

# Check log configuration
kubectl get configmap fluentd-config -n kube-system -o yaml

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/eks
```

## ⚡ Performance Issues

### Issue 1: Slow Pod Startup

**Problem**: Pods taking too long to start

**Solution**:
```bash
# Check pod events
kubectl describe pod todo-backend-xxx -n todo-app

# Check resource requests and limits
kubectl get pod todo-backend-xxx -n todo-app -o yaml | grep -A 10 resources

# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n todo-app

# Common fixes:
# 1. Increase resource requests
# 2. Use smaller base images
# 3. Optimize startup scripts
# 4. Use init containers for setup
```

### Issue 2: High Memory Usage

**Problem**: Pods using too much memory

**Solution**:
```bash
# Check memory usage
kubectl top pods -n todo-app

# Check memory limits
kubectl get pod todo-backend-xxx -n todo-app -o yaml | grep -A 5 resources

# Check memory usage inside pod
kubectl exec -it todo-backend-xxx -n todo-app -- free -h

# Check application memory usage
kubectl exec -it todo-backend-xxx -n todo-app -- ps aux

# Common fixes:
# 1. Increase memory limits
# 2. Optimize application memory usage
# 3. Use memory-efficient base images
# 4. Implement memory monitoring
```

### Issue 3: Slow Database Queries

**Problem**: Database queries taking too long

**Solution**:
```bash
# Check database performance
kubectl exec -it todo-database-xxx -n todo-app -- psql -U postgres -d todoapp -c "
SELECT query, mean_time, calls 
FROM pg_stat_statements 
ORDER BY mean_time DESC 
LIMIT 10;
"

# Check database configuration
kubectl exec -it todo-database-xxx -n todo-app -- psql -U postgres -c "SHOW ALL;"

# Check database indexes
kubectl exec -it todo-database-xxx -n todo-app -- psql -U postgres -d todoapp -c "\di"

# Common fixes:
# 1. Add database indexes
# 2. Optimize queries
# 3. Increase database resources
# 4. Use connection pooling
```

## 💾 Data Migration Issues

### Issue 1: Database Migration Failed

**Problem**: Data not migrated correctly

**Solution**:
```bash
# Check migration logs
kubectl logs -l app=todo-backend -n todo-app | grep -i migration

# Check database tables
kubectl exec -it todo-database-xxx -n todo-app -- psql -U postgres -d todoapp -c "\dt"

# Check table row counts
kubectl exec -it todo-database-xxx -n todo-app -- psql -U postgres -d todoapp -c "
SELECT schemaname,tablename,n_tup_ins,n_tup_upd,n_tup_del 
FROM pg_stat_user_tables;
"

# Re-run migration
python3 migration-scripts/data-migration/data-migration.py \
  --source-config source-config.json \
  --target-config target-config.json
```

### Issue 2: Redis Data Not Migrated

**Problem**: Redis data missing after migration

**Solution**:
```bash
# Check Redis keys
kubectl exec -it todo-redis-xxx -n todo-app -- redis-cli keys "*"

# Check Redis memory usage
kubectl exec -it todo-redis-xxx -n todo-app -- redis-cli info memory

# Check Redis persistence
kubectl exec -it todo-redis-xxx -n todo-app -- redis-cli config get save

# Re-run Redis migration
python3 migration-scripts/data-migration/data-migration.py \
  --source-config source-config.json \
  --target-config target-config.json \
  --data-only
```

## 🔍 Debugging Commands

### General Debugging
```bash
# Check cluster status
kubectl cluster-info

# Check node status
kubectl get nodes

# Check all resources in namespace
kubectl get all -n todo-app

# Check events
kubectl get events -n todo-app --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs -f deployment/todo-backend -n todo-app

# Execute command in pod
kubectl exec -it todo-backend-xxx -n todo-app -- /bin/bash

# Port forward for testing
kubectl port-forward service/todo-backend-service 3000:3000 -n todo-app
```

### Network Debugging
```bash
# Test DNS resolution
kubectl run test-pod --image=busybox --rm -it -- nslookup todo-backend-service.todo-app.svc.cluster.local

# Test connectivity
kubectl run test-pod --image=busybox --rm -it -- wget -qO- http://todo-backend-service:3000/health

# Check network policies
kubectl get networkpolicies -n todo-app

# Check ingress
kubectl get ingress -n todo-app
```

### Storage Debugging
```bash
# Check persistent volumes
kubectl get pv

# Check persistent volume claims
kubectl get pvc -n todo-app

# Check storage classes
kubectl get storageclass

# Check volume mounts
kubectl describe pod todo-database-xxx -n todo-app | grep -A 10 "Mounts:"
```

## 📞 Getting Help

### AWS Support
- **AWS Support Center**: https://console.aws.amazon.com/support/
- **AWS Documentation**: https://docs.aws.amazon.com/
- **AWS Forums**: https://forums.aws.amazon.com/

### Kubernetes Community
- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **Kubernetes Slack**: https://kubernetes.slack.com/
- **Stack Overflow**: https://stackoverflow.com/questions/tagged/kubernetes

### Project-Specific Help
- **GitHub Issues**: Create an issue in the project repository
- **Documentation**: Check the project documentation
- **Community Forums**: Join the project community

## 🎯 Prevention Tips

1. **Test in Staging**: Always test migrations in a staging environment first
2. **Backup Data**: Create backups before starting migration
3. **Monitor Resources**: Keep an eye on resource usage during migration
4. **Use Health Checks**: Implement comprehensive health checks
5. **Document Changes**: Keep track of all configuration changes
6. **Rollback Plan**: Have a rollback plan ready
7. **Gradual Migration**: Consider gradual migration for large applications
8. **Team Training**: Ensure team is trained on Kubernetes concepts

Remember: When in doubt, check the logs first! 📝

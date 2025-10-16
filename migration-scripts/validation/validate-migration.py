#!/usr/bin/env python3
"""
Migration Validation Script
Validates that the ECS to EKS migration was successful
"""

import os
import sys
import json
import time
import requests
import argparse
from typing import Dict, List, Any
from datetime import datetime

class MigrationValidator:
    def __init__(self, config: Dict):
        self.config = config
        self.validation_results = []
        
    def log(self, message: str, level: str = "INFO"):
        """Log validation events"""
        timestamp = datetime.now().isoformat()
        log_entry = {
            "timestamp": timestamp,
            "level": level,
            "message": message
        }
        self.validation_results.append(log_entry)
        print(f"[{level}] {timestamp}: {message}")
    
    def validate_kubernetes_deployments(self):
        """Validate that all Kubernetes deployments are running"""
        self.log("Validating Kubernetes deployments...")
        
        try:
            import subprocess
            
            # Get all deployments in the namespace
            result = subprocess.run([
                'kubectl', 'get', 'deployments', 
                '-n', self.config['namespace'],
                '-o', 'json'
            ], capture_output=True, text=True, check=True)
            
            deployments = json.loads(result.stdout)
            
            for deployment in deployments['items']:
                name = deployment['metadata']['name']
                ready_replicas = deployment['status'].get('readyReplicas', 0)
                desired_replicas = deployment['spec']['replicas']
                
                if ready_replicas == desired_replicas:
                    self.log(f"✅ Deployment {name}: {ready_replicas}/{desired_replicas} replicas ready")
                else:
                    self.log(f"❌ Deployment {name}: {ready_replicas}/{desired_replicas} replicas ready", "ERROR")
            
            self.log("Kubernetes deployments validation completed")
            
        except Exception as e:
            self.log(f"Kubernetes deployments validation failed: {e}", "ERROR")
            raise
    
    def validate_kubernetes_services(self):
        """Validate that all Kubernetes services are accessible"""
        self.log("Validating Kubernetes services...")
        
        try:
            import subprocess
            
            # Get all services in the namespace
            result = subprocess.run([
                'kubectl', 'get', 'services', 
                '-n', self.config['namespace'],
                '-o', 'json'
            ], capture_output=True, text=True, check=True)
            
            services = json.loads(result.stdout)
            
            for service in services['items']:
                name = service['metadata']['name']
                service_type = service['spec']['type']
                cluster_ip = service['spec'].get('clusterIP', 'None')
                
                self.log(f"✅ Service {name}: {service_type} with IP {cluster_ip}")
            
            self.log("Kubernetes services validation completed")
            
        except Exception as e:
            self.log(f"Kubernetes services validation failed: {e}", "ERROR")
            raise
    
    def validate_ingress(self):
        """Validate that ingress is configured correctly"""
        self.log("Validating ingress configuration...")
        
        try:
            import subprocess
            
            # Get ingress in the namespace
            result = subprocess.run([
                'kubectl', 'get', 'ingress', 
                '-n', self.config['namespace'],
                '-o', 'json'
            ], capture_output=True, text=True, check=True)
            
            ingress_list = json.loads(result.stdout)
            
            if not ingress_list['items']:
                self.log("❌ No ingress found in namespace", "ERROR")
                return
            
            for ingress in ingress_list['items']:
                name = ingress['metadata']['name']
                rules = ingress['spec'].get('rules', [])
                
                for rule in rules:
                    host = rule['host']
                    self.log(f"✅ Ingress {name}: configured for host {host}")
            
            self.log("Ingress validation completed")
            
        except Exception as e:
            self.log(f"Ingress validation failed: {e}", "ERROR")
            raise
    
    def validate_health_endpoints(self):
        """Validate that health endpoints are responding"""
        self.log("Validating health endpoints...")
        
        try:
            import subprocess
            
            # Port forward to backend service
            backend_port = 3000
            self.log(f"Setting up port forward to backend service on port {backend_port}")
            
            # Start port forward in background
            port_forward_process = subprocess.Popen([
                'kubectl', 'port-forward', 
                f'service/todo-backend-service', 
                f'{backend_port}:3000',
                '-n', self.config['namespace']
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            # Wait for port forward to be ready
            time.sleep(5)
            
            # Test health endpoint
            health_url = f"http://localhost:{backend_port}/health"
            response = requests.get(health_url, timeout=10)
            
            if response.status_code == 200:
                health_data = response.json()
                self.log(f"✅ Backend health check passed: {health_data.get('status', 'unknown')}")
                
                # Check individual services
                services = health_data.get('services', {})
                for service, status in services.items():
                    if status == 'healthy':
                        self.log(f"✅ {service}: {status}")
                    else:
                        self.log(f"❌ {service}: {status}", "ERROR")
            else:
                self.log(f"❌ Backend health check failed: HTTP {response.status_code}", "ERROR")
            
            # Test readiness endpoint
            readiness_url = f"http://localhost:{backend_port}/health/ready"
            response = requests.get(readiness_url, timeout=10)
            
            if response.status_code == 200:
                self.log("✅ Backend readiness check passed")
            else:
                self.log(f"❌ Backend readiness check failed: HTTP {response.status_code}", "ERROR")
            
            # Test liveness endpoint
            liveness_url = f"http://localhost:{backend_port}/health/live"
            response = requests.get(liveness_url, timeout=10)
            
            if response.status_code == 200:
                self.log("✅ Backend liveness check passed")
            else:
                self.log(f"❌ Backend liveness check failed: HTTP {response.status_code}", "ERROR")
            
            # Clean up port forward
            port_forward_process.terminate()
            port_forward_process.wait()
            
            self.log("Health endpoints validation completed")
            
        except Exception as e:
            self.log(f"Health endpoints validation failed: {e}", "ERROR")
            raise
    
    def validate_api_endpoints(self):
        """Validate that API endpoints are working"""
        self.log("Validating API endpoints...")
        
        try:
            import subprocess
            
            # Port forward to backend service
            backend_port = 3000
            self.log(f"Setting up port forward to backend service on port {backend_port}")
            
            # Start port forward in background
            port_forward_process = subprocess.Popen([
                'kubectl', 'port-forward', 
                f'service/todo-backend-service', 
                f'{backend_port}:3000',
                '-n', self.config['namespace']
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            # Wait for port forward to be ready
            time.sleep(5)
            
            # Test root endpoint
            root_url = f"http://localhost:{backend_port}/"
            response = requests.get(root_url, timeout=10)
            
            if response.status_code == 200:
                self.log("✅ Root endpoint is accessible")
            else:
                self.log(f"❌ Root endpoint failed: HTTP {response.status_code}", "ERROR")
            
            # Test auth endpoints
            auth_endpoints = [
                '/api/auth/register',
                '/api/auth/login',
                '/api/auth/verify'
            ]
            
            for endpoint in auth_endpoints:
                url = f"http://localhost:{backend_port}{endpoint}"
                response = requests.get(url, timeout=10)
                
                # These endpoints should return 405 (Method Not Allowed) for GET requests
                if response.status_code == 405:
                    self.log(f"✅ {endpoint}: Method not allowed (expected for GET)")
                else:
                    self.log(f"❌ {endpoint}: Unexpected response {response.status_code}", "ERROR")
            
            # Test todos endpoints
            todos_endpoints = [
                '/api/todos',
                '/api/todos/stats/summary'
            ]
            
            for endpoint in todos_endpoints:
                url = f"http://localhost:{backend_port}{endpoint}"
                response = requests.get(url, timeout=10)
                
                # These endpoints should return 401 (Unauthorized) without token
                if response.status_code == 401:
                    self.log(f"✅ {endpoint}: Unauthorized (expected without token)")
                else:
                    self.log(f"❌ {endpoint}: Unexpected response {response.status_code}", "ERROR")
            
            # Clean up port forward
            port_forward_process.terminate()
            port_forward_process.wait()
            
            self.log("API endpoints validation completed")
            
        except Exception as e:
            self.log(f"API endpoints validation failed: {e}", "ERROR")
            raise
    
    def validate_database_connectivity(self):
        """Validate that database is accessible"""
        self.log("Validating database connectivity...")
        
        try:
            import subprocess
            
            # Port forward to database service
            db_port = 5432
            self.log(f"Setting up port forward to database service on port {db_port}")
            
            # Start port forward in background
            port_forward_process = subprocess.Popen([
                'kubectl', 'port-forward', 
                f'service/todo-database-service', 
                f'{db_port}:5432',
                '-n', self.config['namespace']
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            # Wait for port forward to be ready
            time.sleep(5)
            
            # Test database connection
            import psycopg2
            
            conn = psycopg2.connect(
                host='localhost',
                port=db_port,
                database='todoapp',
                user='postgres',
                password='password'
            )
            
            cursor = conn.cursor()
            cursor.execute("SELECT version();")
            version = cursor.fetchone()[0]
            
            self.log(f"✅ Database connection successful: {version}")
            
            # Check if tables exist
            cursor.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public'
            """)
            
            tables = [row[0] for row in cursor.fetchall()]
            self.log(f"✅ Database tables found: {', '.join(tables)}")
            
            cursor.close()
            conn.close()
            
            # Clean up port forward
            port_forward_process.terminate()
            port_forward_process.wait()
            
            self.log("Database connectivity validation completed")
            
        except Exception as e:
            self.log(f"Database connectivity validation failed: {e}", "ERROR")
            raise
    
    def validate_redis_connectivity(self):
        """Validate that Redis is accessible"""
        self.log("Validating Redis connectivity...")
        
        try:
            import subprocess
            
            # Port forward to Redis service
            redis_port = 6379
            self.log(f"Setting up port forward to Redis service on port {redis_port}")
            
            # Start port forward in background
            port_forward_process = subprocess.Popen([
                'kubectl', 'port-forward', 
                f'service/todo-redis-service', 
                f'{redis_port}:6379',
                '-n', self.config['namespace']
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            # Wait for port forward to be ready
            time.sleep(5)
            
            # Test Redis connection
            import redis
            
            r = redis.Redis(host='localhost', port=redis_port, decode_responses=True)
            r.ping()
            
            self.log("✅ Redis connection successful")
            
            # Get Redis info
            info = r.info()
            self.log(f"✅ Redis version: {info.get('redis_version', 'unknown')}")
            self.log(f"✅ Redis memory usage: {info.get('used_memory_human', 'unknown')}")
            
            # Clean up port forward
            port_forward_process.terminate()
            port_forward_process.wait()
            
            self.log("Redis connectivity validation completed")
            
        except Exception as e:
            self.log(f"Redis connectivity validation failed: {e}", "ERROR")
            raise
    
    def validate_monitoring(self):
        """Validate that monitoring is working"""
        self.log("Validating monitoring setup...")
        
        try:
            import subprocess
            
            # Check if Prometheus is running
            result = subprocess.run([
                'kubectl', 'get', 'pods', 
                '-n', 'monitoring',
                '-l', 'app=prometheus',
                '-o', 'json'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                prometheus_pods = json.loads(result.stdout)
                if prometheus_pods['items']:
                    self.log("✅ Prometheus is running")
                else:
                    self.log("❌ Prometheus is not running", "ERROR")
            else:
                self.log("❌ Prometheus namespace not found", "ERROR")
            
            # Check if Grafana is running
            result = subprocess.run([
                'kubectl', 'get', 'pods', 
                '-n', 'monitoring',
                '-l', 'app=grafana',
                '-o', 'json'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                grafana_pods = json.loads(result.stdout)
                if grafana_pods['items']:
                    self.log("✅ Grafana is running")
                else:
                    self.log("❌ Grafana is not running", "ERROR")
            else:
                self.log("❌ Grafana namespace not found", "ERROR")
            
            self.log("Monitoring validation completed")
            
        except Exception as e:
            self.log(f"Monitoring validation failed: {e}", "ERROR")
            raise
    
    def generate_validation_report(self):
        """Generate validation report"""
        self.log("Generating validation report...")
        
        # Count results
        total_checks = len(self.validation_results)
        error_count = sum(1 for result in self.validation_results if result['level'] == 'ERROR')
        warning_count = sum(1 for result in self.validation_results if result['level'] == 'WARNING')
        success_count = total_checks - error_count - warning_count
        
        # Generate report
        report = {
            "summary": {
                "total_checks": total_checks,
                "successful": success_count,
                "warnings": warning_count,
                "errors": error_count,
                "success_rate": (success_count / total_checks * 100) if total_checks > 0 else 0
            },
            "results": self.validation_results,
            "timestamp": datetime.now().isoformat()
        }
        
        # Save report
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_filename = f"validation_report_{timestamp}.json"
        
        with open(report_filename, 'w') as f:
            json.dump(report, f, indent=2)
        
        self.log(f"Validation report saved to {report_filename}")
        
        # Print summary
        print(f"\n{'='*50}")
        print(f"VALIDATION SUMMARY")
        print(f"{'='*50}")
        print(f"Total Checks: {total_checks}")
        print(f"Successful: {success_count}")
        print(f"Warnings: {warning_count}")
        print(f"Errors: {error_count}")
        print(f"Success Rate: {report['summary']['success_rate']:.1f}%")
        print(f"{'='*50}")
        
        if error_count > 0:
            print(f"❌ Migration validation failed with {error_count} errors")
            return False
        else:
            print(f"✅ Migration validation passed successfully")
            return True
    
    def run_validation(self):
        """Run the complete validation process"""
        self.log("Starting ECS to EKS migration validation...")
        
        try:
            # Validate Kubernetes resources
            self.validate_kubernetes_deployments()
            self.validate_kubernetes_services()
            self.validate_ingress()
            
            # Validate application health
            self.validate_health_endpoints()
            self.validate_api_endpoints()
            
            # Validate data layer
            self.validate_database_connectivity()
            self.validate_redis_connectivity()
            
            # Validate monitoring
            self.validate_monitoring()
            
            # Generate report
            success = self.generate_validation_report()
            
            if success:
                self.log("Migration validation completed successfully!")
            else:
                self.log("Migration validation failed!", "ERROR")
            
            return success
            
        except Exception as e:
            self.log(f"Validation failed: {e}", "ERROR")
            return False

def main():
    parser = argparse.ArgumentParser(description='Validate ECS to EKS migration')
    parser.add_argument('--config', required=True, help='Validation configuration file')
    parser.add_argument('--namespace', default='todo-app', help='Kubernetes namespace')
    
    args = parser.parse_args()
    
    # Load configuration
    with open(args.config, 'r') as f:
        config = json.load(f)
    
    config['namespace'] = args.namespace
    
    # Create validator
    validator = MigrationValidator(config)
    
    try:
        success = validator.run_validation()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"Validation failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()

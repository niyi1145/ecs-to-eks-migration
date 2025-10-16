#!/usr/bin/env python3
"""
ECS to Kubernetes Migration Tool
Converts ECS task definitions and service definitions to Kubernetes manifests
"""

import json
import yaml
import argparse
import os
import sys
from typing import Dict, List, Any
from pathlib import Path

class ECSToK8sConverter:
    def __init__(self):
        self.namespace = "todo-app"
        self.registry = "ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com"
        
    def convert_task_definition_to_deployment(self, task_def: Dict) -> Dict:
        """Convert ECS task definition to Kubernetes deployment"""
        family = task_def.get('family', 'unknown')
        containers = task_def.get('containerDefinitions', [])
        
        deployment = {
            'apiVersion': 'apps/v1',
            'kind': 'Deployment',
            'metadata': {
                'name': family,
                'namespace': self.namespace,
                'labels': {
                    'app': family,
                    'version': 'v1',
                    'component': self._get_component_type(family)
                }
            },
            'spec': {
                'replicas': 2 if 'backend' in family or 'frontend' in family else 1,
                'selector': {
                    'matchLabels': {
                        'app': family
                    }
                },
                'template': {
                    'metadata': {
                        'labels': {
                            'app': family,
                            'version': 'v1',
                            'component': self._get_component_type(family)
                        }
                    },
                    'spec': {
                        'serviceAccountName': f'{family}-sa',
                        'securityContext': {
                            'runAsNonRoot': True,
                            'runAsUser': 1001,
                            'runAsGroup': 1001,
                            'fsGroup': 1001
                        },
                        'containers': [],
                        'restartPolicy': 'Always',
                        'terminationGracePeriodSeconds': 30
                    }
                }
            }
        }
        
        for container in containers:
            k8s_container = self._convert_container(container, family)
            deployment['spec']['template']['spec']['containers'].append(k8s_container)
            
        return deployment
    
    def convert_service_definition_to_service(self, service_def: Dict) -> Dict:
        """Convert ECS service definition to Kubernetes service"""
        service_name = service_def.get('serviceName', 'unknown')
        task_definition = service_def.get('taskDefinition', 'unknown')
        
        service = {
            'apiVersion': 'v1',
            'kind': 'Service',
            'metadata': {
                'name': f'{service_name}-service',
                'namespace': self.namespace,
                'labels': {
                    'app': task_definition,
                    'component': self._get_component_type(task_definition)
                }
            },
            'spec': {
                'type': 'ClusterIP',
                'ports': [],
                'selector': {
                    'app': task_definition
                }
            }
        }
        
        # Extract port from task definition or use defaults
        port = self._get_default_port(task_definition)
        service['spec']['ports'].append({
            'port': port,
            'targetPort': port,
            'protocol': 'TCP',
            'name': self._get_port_name(port)
        })
        
        return service
    
    def _convert_container(self, container: Dict, family: str) -> Dict:
        """Convert ECS container definition to Kubernetes container"""
        name = container.get('name', 'container')
        image = container.get('image', '')
        
        # Replace ECR registry if needed
        if 'dkr.ecr' in image:
            image = image.replace('ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com', self.registry)
        
        k8s_container = {
            'name': name,
            'image': image,
            'ports': [],
            'env': [],
            'resources': {
                'requests': {
                    'memory': '256Mi',
                    'cpu': '100m'
                },
                'limits': {
                    'memory': '512Mi',
                    'cpu': '200m'
                }
            },
            'securityContext': {
                'allowPrivilegeEscalation': False,
                'readOnlyRootFilesystem': True,
                'runAsNonRoot': True,
                'runAsUser': 1001,
                'capabilities': {
                    'drop': ['ALL']
                }
            }
        }
        
        # Convert port mappings
        for port_mapping in container.get('portMappings', []):
            k8s_container['ports'].append({
                'containerPort': port_mapping.get('containerPort', 80),
                'name': self._get_port_name(port_mapping.get('containerPort', 80)),
                'protocol': port_mapping.get('protocol', 'TCP')
            })
        
        # Convert environment variables
        for env_var in container.get('environment', []):
            k8s_container['env'].append({
                'name': env_var.get('name', ''),
                'value': env_var.get('value', '')
            })
        
        # Convert secrets
        for secret in container.get('secrets', []):
            k8s_container['env'].append({
                'name': secret.get('name', ''),
                'valueFrom': {
                    'secretKeyRef': {
                        'name': f'{family}-secrets',
                        'key': secret.get('name', '').lower().replace('_', '-')
                    }
                }
            })
        
        # Add health checks
        if 'healthCheck' in container:
            health_check = container['healthCheck']
            if 'httpGet' in health_check.get('command', [''])[0]:
                k8s_container['livenessProbe'] = {
                    'httpGet': {
                        'path': '/health',
                        'port': k8s_container['ports'][0]['containerPort'] if k8s_container['ports'] else 80
                    },
                    'initialDelaySeconds': 30,
                    'periodSeconds': 10,
                    'timeoutSeconds': 5,
                    'failureThreshold': 3
                }
                k8s_container['readinessProbe'] = {
                    'httpGet': {
                        'path': '/health',
                        'port': k8s_container['ports'][0]['containerPort'] if k8s_container['ports'] else 80
                    },
                    'initialDelaySeconds': 5,
                    'periodSeconds': 5,
                    'timeoutSeconds': 3,
                    'failureThreshold': 3
                }
        
        return k8s_container
    
    def _get_component_type(self, name: str) -> str:
        """Determine component type from name"""
        if 'backend' in name:
            return 'backend'
        elif 'frontend' in name:
            return 'frontend'
        elif 'database' in name or 'postgres' in name:
            return 'database'
        elif 'redis' in name:
            return 'redis'
        else:
            return 'service'
    
    def _get_default_port(self, name: str) -> int:
        """Get default port based on service type"""
        if 'backend' in name:
            return 3000
        elif 'frontend' in name:
            return 3000
        elif 'database' in name or 'postgres' in name:
            return 5432
        elif 'redis' in name:
            return 6379
        else:
            return 80
    
    def _get_port_name(self, port: int) -> str:
        """Get port name based on port number"""
        if port == 3000:
            return 'http'
        elif port == 5432:
            return 'postgres'
        elif port == 6379:
            return 'redis'
        else:
            return 'http'
    
    def create_service_account(self, name: str) -> Dict:
        """Create Kubernetes service account"""
        return {
            'apiVersion': 'v1',
            'kind': 'ServiceAccount',
            'metadata': {
                'name': f'{name}-sa',
                'namespace': self.namespace,
                'labels': {
                    'app': name,
                    'component': self._get_component_type(name)
                }
            }
        }
    
    def create_secret(self, name: str, secrets: List[Dict]) -> Dict:
        """Create Kubernetes secret from ECS secrets"""
        secret_data = {}
        for secret in secrets:
            key = secret.get('name', '').lower().replace('_', '-')
            secret_data[key] = 'base64-encoded-value'  # Placeholder
        
        return {
            'apiVersion': 'v1',
            'kind': 'Secret',
            'metadata': {
                'name': f'{name}-secrets',
                'namespace': self.namespace,
                'labels': {
                    'app': name,
                    'component': self._get_component_type(name)
                }
            },
            'type': 'Opaque',
            'data': secret_data
        }
    
    def convert_all(self, input_dir: str, output_dir: str):
        """Convert all ECS definitions to Kubernetes manifests"""
        input_path = Path(input_dir)
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        # Process task definitions
        task_defs_dir = input_path / 'task-definitions'
        if task_defs_dir.exists():
            for task_file in task_defs_dir.glob('*.json'):
                with open(task_file, 'r') as f:
                    task_def = json.load(f)
                
                # Convert to deployment
                deployment = self.convert_task_definition_to_deployment(task_def)
                
                # Save deployment
                family = task_def.get('family', 'unknown')
                deployment_file = output_path / f'{family}-deployment.yaml'
                with open(deployment_file, 'w') as f:
                    yaml.dump(deployment, f, default_flow_style=False, sort_keys=False)
                
                # Create service account
                sa = self.create_service_account(family)
                sa_file = output_path / f'{family}-serviceaccount.yaml'
                with open(sa_file, 'w') as f:
                    yaml.dump(sa, f, default_flow_style=False, sort_keys=False)
                
                # Create secret if needed
                containers = task_def.get('containerDefinitions', [])
                secrets = []
                for container in containers:
                    secrets.extend(container.get('secrets', []))
                
                if secrets:
                    secret = self.create_secret(family, secrets)
                    secret_file = output_path / f'{family}-secret.yaml'
                    with open(secret_file, 'w') as f:
                        yaml.dump(secret, f, default_flow_style=False, sort_keys=False)
        
        # Process service definitions
        services_dir = input_path / 'services'
        if services_dir.exists():
            for service_file in services_dir.glob('*.json'):
                with open(service_file, 'r') as f:
                    service_def = json.load(f)
                
                # Convert to service
                service = self.convert_service_definition_to_service(service_def)
                
                # Save service
                service_name = service_def.get('serviceName', 'unknown')
                k8s_service_file = output_path / f'{service_name}-service.yaml'
                with open(k8s_service_file, 'w') as f:
                    yaml.dump(service, f, default_flow_style=False, sort_keys=False)
        
        print(f"✅ Conversion complete! Output saved to {output_dir}")

def main():
    parser = argparse.ArgumentParser(description='Convert ECS definitions to Kubernetes manifests')
    parser.add_argument('--input', '-i', required=True, help='Input directory containing ECS definitions')
    parser.add_argument('--output', '-o', required=True, help='Output directory for Kubernetes manifests')
    parser.add_argument('--namespace', '-n', default='todo-app', help='Kubernetes namespace')
    parser.add_argument('--registry', '-r', default='ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com', help='Container registry')
    
    args = parser.parse_args()
    
    converter = ECSToK8sConverter()
    converter.namespace = args.namespace
    converter.registry = args.registry
    
    try:
        converter.convert_all(args.input, args.output)
    except Exception as e:
        print(f"❌ Error during conversion: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()

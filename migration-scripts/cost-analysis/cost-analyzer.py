#!/usr/bin/env python3
"""
Cost Analysis Tool for ECS to EKS Migration
Calculates and compares costs between ECS and EKS deployments
"""

import json
import argparse
import sys
from typing import Dict, List, Any
from datetime import datetime, timedelta
from dataclasses import dataclass

@dataclass
class ResourceCost:
    """Represents the cost of a resource"""
    name: str
    type: str
    monthly_cost: float
    hourly_cost: float
    unit: str
    description: str

class CostAnalyzer:
    def __init__(self, region: str = "us-east-1"):
        self.region = region
        self.costs = {
            "ecs": {},
            "eks": {}
        }
        
        # AWS Pricing (as of 2024 - these are approximate and should be updated)
        self.pricing = {
            "ec2": {
                "t3.micro": {"hourly": 0.0104, "monthly": 7.5},
                "t3.small": {"hourly": 0.0208, "monthly": 15.0},
                "t3.medium": {"hourly": 0.0416, "monthly": 30.0},
                "t3.large": {"hourly": 0.0832, "monthly": 60.0},
                "t3.xlarge": {"hourly": 0.1664, "monthly": 120.0},
            },
            "fargate": {
                "cpu": {"per_vcpu_hour": 0.04048, "per_vcpu_month": 29.15},
                "memory": {"per_gb_hour": 0.004445, "per_gb_month": 3.20},
            },
            "eks": {
                "control_plane": {"hourly": 0.10, "monthly": 72.0},
            },
            "alb": {
                "hourly": 0.0225, "monthly": 16.2,
                "lcu_hourly": 0.008, "lcu_monthly": 5.76,
            },
            "nlb": {
                "hourly": 0.0225, "monthly": 16.2,
                "nlc_hourly": 0.006, "nlc_monthly": 4.32,
            },
            "efs": {
                "storage": {"per_gb_month": 0.30},
                "throughput": {"per_mibps_month": 6.0},
            },
            "ebs": {
                "gp3": {"per_gb_month": 0.08},
                "gp2": {"per_gb_month": 0.10},
            },
            "nat_gateway": {
                "hourly": 0.045, "monthly": 32.4,
                "data_processed": {"per_gb": 0.045},
            },
            "data_transfer": {
                "internet_egress": {"per_gb": 0.09},
                "az_transfer": {"per_gb": 0.01},
            }
        }
    
    def calculate_ecs_costs(self, config: Dict) -> Dict[str, ResourceCost]:
        """Calculate ECS deployment costs"""
        costs = {}
        
        # ECS Cluster (no additional cost for cluster itself)
        costs["ecs_cluster"] = ResourceCost(
            name="ECS Cluster",
            type="cluster",
            monthly_cost=0.0,
            hourly_cost=0.0,
            unit="cluster",
            description="ECS cluster management (included in service costs)"
        )
        
        # Fargate Tasks
        for service_name, service_config in config.get("services", {}).items():
            cpu = service_config.get("cpu", 256)  # in CPU units (256 = 0.25 vCPU)
            memory = service_config.get("memory", 512)  # in MB
            desired_count = service_config.get("desired_count", 1)
            
            vcpu = cpu / 1024  # Convert to vCPU
            memory_gb = memory / 1024  # Convert to GB
            
            # Fargate pricing
            cpu_cost_per_hour = vcpu * self.pricing["fargate"]["cpu"]["per_vcpu_hour"]
            memory_cost_per_hour = memory_gb * self.pricing["fargate"]["memory"]["per_gb_hour"]
            
            total_hourly_cost = (cpu_cost_per_hour + memory_cost_per_hour) * desired_count
            total_monthly_cost = total_hourly_cost * 24 * 30
            
            costs[f"fargate_{service_name}"] = ResourceCost(
                name=f"Fargate - {service_name}",
                type="compute",
                monthly_cost=total_monthly_cost,
                hourly_cost=total_hourly_cost,
                unit="task",
                description=f"Fargate task: {cpu} CPU units, {memory}MB memory, {desired_count} tasks"
            )
        
        # Application Load Balancer
        alb_config = config.get("load_balancer", {})
        if alb_config.get("type") == "alb":
            alb_hourly = self.pricing["alb"]["hourly"]
            alb_monthly = self.pricing["alb"]["monthly"]
            
            # Estimate LCU usage (simplified)
            estimated_lcu = alb_config.get("estimated_lcu", 2)
            lcu_hourly = estimated_lcu * self.pricing["alb"]["lcu_hourly"]
            lcu_monthly = estimated_lcu * self.pricing["alb"]["lcu_monthly"]
            
            total_alb_hourly = alb_hourly + lcu_hourly
            total_alb_monthly = alb_monthly + lcu_monthly
            
            costs["alb"] = ResourceCost(
                name="Application Load Balancer",
                type="networking",
                monthly_cost=total_alb_monthly,
                hourly_cost=total_alb_hourly,
                unit="load_balancer",
                description=f"ALB with estimated {estimated_lcu} LCUs"
            )
        
        # EFS Storage
        efs_config = config.get("storage", {}).get("efs", {})
        if efs_config:
            storage_gb = efs_config.get("size_gb", 100)
            throughput_mibps = efs_config.get("throughput_mibps", 100)
            
            storage_cost = storage_gb * self.pricing["efs"]["storage"]["per_gb_month"]
            throughput_cost = throughput_mibps * self.pricing["efs"]["throughput"]["per_mibps_month"]
            
            costs["efs"] = ResourceCost(
                name="EFS Storage",
                type="storage",
                monthly_cost=storage_cost + throughput_cost,
                hourly_cost=(storage_cost + throughput_cost) / (24 * 30),
                unit="gb",
                description=f"EFS: {storage_gb}GB storage, {throughput_mibps} MiB/s throughput"
            )
        
        # NAT Gateway
        nat_config = config.get("networking", {}).get("nat_gateway", {})
        if nat_config.get("enabled", True):
            nat_count = nat_config.get("count", 2)
            nat_hourly = nat_count * self.pricing["nat_gateway"]["hourly"]
            nat_monthly = nat_count * self.pricing["nat_gateway"]["monthly"]
            
            costs["nat_gateway"] = ResourceCost(
                name="NAT Gateway",
                type="networking",
                monthly_cost=nat_monthly,
                hourly_cost=nat_hourly,
                unit="gateway",
                description=f"{nat_count} NAT Gateways"
            )
        
        # Data Transfer (estimated)
        data_transfer_gb = config.get("data_transfer", {}).get("monthly_gb", 100)
        data_transfer_cost = data_transfer_gb * self.pricing["data_transfer"]["internet_egress"]["per_gb"]
        
        costs["data_transfer"] = ResourceCost(
            name="Data Transfer",
            type="networking",
            monthly_cost=data_transfer_cost,
            hourly_cost=data_transfer_cost / (24 * 30),
            unit="gb",
            description=f"Estimated {data_transfer_gb}GB monthly data transfer"
        )
        
        return costs
    
    def calculate_eks_costs(self, config: Dict) -> Dict[str, ResourceCost]:
        """Calculate EKS deployment costs"""
        costs = {}
        
        # EKS Control Plane
        costs["eks_control_plane"] = ResourceCost(
            name="EKS Control Plane",
            type="cluster",
            monthly_cost=self.pricing["eks"]["control_plane"]["monthly"],
            hourly_cost=self.pricing["eks"]["control_plane"]["hourly"],
            unit="cluster",
            description="EKS managed control plane"
        )
        
        # Worker Nodes
        node_config = config.get("node_group", {})
        instance_type = node_config.get("instance_type", "t3.medium")
        desired_size = node_config.get("desired_size", 2)
        
        if instance_type in self.pricing["ec2"]:
            node_hourly = self.pricing["ec2"][instance_type]["hourly"] * desired_size
            node_monthly = self.pricing["ec2"][instance_type]["monthly"] * desired_size
            
            costs["worker_nodes"] = ResourceCost(
                name="Worker Nodes",
                type="compute",
                monthly_cost=node_monthly,
                hourly_cost=node_hourly,
                unit="instance",
                description=f"{desired_size} x {instance_type} instances"
            )
        
        # Application Load Balancer (same as ECS)
        alb_config = config.get("load_balancer", {})
        if alb_config.get("type") == "alb":
            alb_hourly = self.pricing["alb"]["hourly"]
            alb_monthly = self.pricing["alb"]["monthly"]
            
            estimated_lcu = alb_config.get("estimated_lcu", 2)
            lcu_hourly = estimated_lcu * self.pricing["alb"]["lcu_hourly"]
            lcu_monthly = estimated_lcu * self.pricing["alb"]["lcu_monthly"]
            
            total_alb_hourly = alb_hourly + lcu_hourly
            total_alb_monthly = alb_monthly + lcu_monthly
            
            costs["alb"] = ResourceCost(
                name="Application Load Balancer",
                type="networking",
                monthly_cost=total_alb_monthly,
                hourly_cost=total_alb_hourly,
                unit="load_balancer",
                description=f"ALB with estimated {estimated_lcu} LCUs"
            )
        
        # EBS Storage
        ebs_config = config.get("storage", {}).get("ebs", {})
        if ebs_config:
            storage_gb = ebs_config.get("size_gb", 100)
            storage_type = ebs_config.get("type", "gp3")
            
            if storage_type in self.pricing["ebs"]:
                storage_cost = storage_gb * self.pricing["ebs"][storage_type]["per_gb_month"]
                
                costs["ebs"] = ResourceCost(
                    name="EBS Storage",
                    type="storage",
                    monthly_cost=storage_cost,
                    hourly_cost=storage_cost / (24 * 30),
                    unit="gb",
                    description=f"EBS {storage_type}: {storage_gb}GB"
                )
        
        # NAT Gateway (same as ECS)
        nat_config = config.get("networking", {}).get("nat_gateway", {})
        if nat_config.get("enabled", True):
            nat_count = nat_config.get("count", 2)
            nat_hourly = nat_count * self.pricing["nat_gateway"]["hourly"]
            nat_monthly = nat_count * self.pricing["nat_gateway"]["monthly"]
            
            costs["nat_gateway"] = ResourceCost(
                name="NAT Gateway",
                type="networking",
                monthly_cost=nat_monthly,
                hourly_cost=nat_hourly,
                unit="gateway",
                description=f"{nat_count} NAT Gateways"
            )
        
        # Data Transfer (same as ECS)
        data_transfer_gb = config.get("data_transfer", {}).get("monthly_gb", 100)
        data_transfer_cost = data_transfer_gb * self.pricing["data_transfer"]["internet_egress"]["per_gb"]
        
        costs["data_transfer"] = ResourceCost(
            name="Data Transfer",
            type="networking",
            monthly_cost=data_transfer_cost,
            hourly_cost=data_transfer_cost / (24 * 30),
            unit="gb",
            description=f"Estimated {data_transfer_gb}GB monthly data transfer"
        )
        
        return costs
    
    def generate_cost_report(self, ecs_config: Dict, eks_config: Dict) -> Dict:
        """Generate comprehensive cost comparison report"""
        ecs_costs = self.calculate_ecs_costs(ecs_config)
        eks_costs = self.calculate_eks_costs(eks_config)
        
        # Calculate totals
        ecs_total_monthly = sum(cost.monthly_cost for cost in ecs_costs.values())
        ecs_total_hourly = sum(cost.hourly_cost for cost in ecs_costs.values())
        
        eks_total_monthly = sum(cost.monthly_cost for cost in eks_costs.values())
        eks_total_hourly = sum(cost.hourly_cost for cost in eks_costs.values())
        
        # Calculate savings
        monthly_savings = ecs_total_monthly - eks_total_monthly
        hourly_savings = ecs_total_hourly - eks_total_hourly
        savings_percentage = (monthly_savings / ecs_total_monthly * 100) if ecs_total_monthly > 0 else 0
        
        report = {
            "timestamp": datetime.now().isoformat(),
            "region": self.region,
            "summary": {
                "ecs": {
                    "total_monthly": round(ecs_total_monthly, 2),
                    "total_hourly": round(ecs_total_hourly, 4),
                    "resource_count": len(ecs_costs)
                },
                "eks": {
                    "total_monthly": round(eks_total_monthly, 2),
                    "total_hourly": round(eks_total_hourly, 4),
                    "resource_count": len(eks_costs)
                },
                "savings": {
                    "monthly": round(monthly_savings, 2),
                    "hourly": round(hourly_savings, 4),
                    "percentage": round(savings_percentage, 2)
                }
            },
            "ecs_costs": {
                name: {
                    "type": cost.type,
                    "monthly_cost": round(cost.monthly_cost, 2),
                    "hourly_cost": round(cost.hourly_cost, 4),
                    "unit": cost.unit,
                    "description": cost.description
                }
                for name, cost in ecs_costs.items()
            },
            "eks_costs": {
                name: {
                    "type": cost.type,
                    "monthly_cost": round(cost.monthly_cost, 2),
                    "hourly_cost": round(cost.hourly_cost, 4),
                    "unit": cost.unit,
                    "description": cost.description
                }
                for name, cost in eks_costs.items()
            },
            "recommendations": self._generate_recommendations(ecs_costs, eks_costs, monthly_savings)
        }
        
        return report
    
    def _generate_recommendations(self, ecs_costs: Dict, eks_costs: Dict, savings: float) -> List[str]:
        """Generate cost optimization recommendations"""
        recommendations = []
        
        if savings > 0:
            recommendations.append(f"EKS is ${abs(savings):.2f} cheaper per month than ECS")
        elif savings < 0:
            recommendations.append(f"ECS is ${abs(savings):.2f} cheaper per month than EKS")
        else:
            recommendations.append("ECS and EKS have similar costs")
        
        # Analyze individual components
        ecs_total = sum(cost.monthly_cost for cost in ecs_costs.values())
        eks_total = sum(cost.monthly_cost for cost in eks_costs.values())
        
        if ecs_total > 0:
            # Find most expensive ECS components
            ecs_sorted = sorted(ecs_costs.items(), key=lambda x: x[1].monthly_cost, reverse=True)
            if ecs_sorted:
                most_expensive = ecs_sorted[0]
                if most_expensive[1].monthly_cost > ecs_total * 0.3:  # More than 30% of total
                    recommendations.append(f"Consider optimizing {most_expensive[0]} (${most_expensive[1].monthly_cost:.2f}/month)")
        
        if eks_total > 0:
            # Find most expensive EKS components
            eks_sorted = sorted(eks_costs.items(), key=lambda x: x[1].monthly_cost, reverse=True)
            if eks_sorted:
                most_expensive = eks_sorted[0]
                if most_expensive[1].monthly_cost > eks_total * 0.3:  # More than 30% of total
                    recommendations.append(f"Consider optimizing {most_expensive[0]} (${most_expensive[1].monthly_cost:.2f}/month)")
        
        # General recommendations
        recommendations.extend([
            "Consider using Spot instances for non-production workloads",
            "Implement auto-scaling to optimize resource usage",
            "Use Reserved Instances for predictable workloads",
            "Monitor and optimize data transfer costs",
            "Regularly review and right-size your resources"
        ])
        
        return recommendations
    
    def print_report(self, report: Dict):
        """Print a formatted cost report"""
        print("=" * 80)
        print("ECS vs EKS COST ANALYSIS REPORT")
        print("=" * 80)
        print(f"Generated: {report['timestamp']}")
        print(f"Region: {report['region']}")
        print()
        
        # Summary
        summary = report['summary']
        print("COST SUMMARY")
        print("-" * 40)
        print(f"ECS Total Monthly:  ${summary['ecs']['total_monthly']:>10.2f}")
        print(f"EKS Total Monthly:  ${summary['eks']['total_monthly']:>10.2f}")
        print(f"Monthly Difference: ${summary['savings']['monthly']:>10.2f}")
        print(f"Savings Percentage: {summary['savings']['percentage']:>9.2f}%")
        print()
        
        # ECS Costs
        print("ECS COSTS BREAKDOWN")
        print("-" * 40)
        for name, cost in report['ecs_costs'].items():
            print(f"{name:<25} ${cost['monthly_cost']:>8.2f}/month ({cost['description']})")
        print()
        
        # EKS Costs
        print("EKS COSTS BREAKDOWN")
        print("-" * 40)
        for name, cost in report['eks_costs'].items():
            print(f"{name:<25} ${cost['monthly_cost']:>8.2f}/month ({cost['description']})")
        print()
        
        # Recommendations
        print("RECOMMENDATIONS")
        print("-" * 40)
        for i, rec in enumerate(report['recommendations'], 1):
            print(f"{i}. {rec}")
        print()
        
        print("=" * 80)

def main():
    parser = argparse.ArgumentParser(description='Analyze costs for ECS vs EKS migration')
    parser.add_argument('--ecs-config', required=True, help='ECS configuration file')
    parser.add_argument('--eks-config', required=True, help='EKS configuration file')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--output', help='Output file for JSON report')
    parser.add_argument('--format', choices=['text', 'json'], default='text', help='Output format')
    
    args = parser.parse_args()
    
    # Load configurations
    with open(args.ecs_config, 'r') as f:
        ecs_config = json.load(f)
    
    with open(args.eks_config, 'r') as f:
        eks_config = json.load(f)
    
    # Generate cost analysis
    analyzer = CostAnalyzer(args.region)
    report = analyzer.generate_cost_report(ecs_config, eks_config)
    
    # Output results
    if args.format == 'text':
        analyzer.print_report(report)
    else:
        print(json.dumps(report, indent=2))
    
    # Save to file if requested
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"Report saved to {args.output}")

if __name__ == '__main__':
    main()

# Repository Overview

This note provides a quick orientation for contributors.

## What this repository contains

- An ECS reference implementation for a Todo microservices app (`ecs-application/`).
- An EKS target implementation for the same app (`eks-application/`).
- Migration tooling and automation (`migration-scripts/`).
- Migration and compliance documentation (`documentation/` and top-level summary docs).

## Key runtime components

- **Backend API**: Node.js + Express + PostgreSQL + Redis.
- **Frontend**: React app served with NGINX.
- **Infrastructure as Code**: Terraform for ECS and EKS environments.
- **Kubernetes artifacts**: Deployments, services, ingress, monitoring, and security policies.

## Suggested starting points

1. Read `README.md` for project intent and structure.
2. Review `migration-scripts/automation/migrate.sh` for the end-to-end workflow.
3. Review `migration-scripts/validation/validate-migration.py` for post-migration checks.
4. Inspect backend behavior in `ecs-application/backend/server.js`.

## Quick observations

- The repo is documentation-rich and intended as an end-to-end migration example.
- Scripts assume a live AWS/Kubernetes environment and installed CLIs.
- There are multiple top-level summary markdown files for different audiences (project, migration, FedRAMP).

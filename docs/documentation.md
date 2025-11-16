# Hybrid Clean Architecture: Documentation & Migration Guide

This document specifies the required CLI tool and provides a guide for migrating from a classic layered architecture to this Vertical Slice Architecture (VSA) with a Strict Domain Core.

---

## 1. Overview

This architecture combines:
- **Vertical Slice Architecture (VSA)** for feature organization
- **Clean Architecture principles** with a strict domain core
- **MediatR** for CQRS and cross-cutting concerns
- **Modular Monolith** approach for deployment simplicity

---

## 2. CLI Tool Specification: Feature Scaffolding Tool

To achieve high feature velocity, a custom scaffolding tool automates the creation of new Vertical Slices (Features).

### Command Syntax

```bash
scaffold-feature --name <FeatureName> --usecase-type <Type> --entity <EntityName>

# Example:
scaffold-feature -n CreateProduct -ut command -e Product
```

### Parameters

| Parameter | Alias | Description | Values |
|-----------|-------|-------------|--------|
| `--name` | `-n` | The name of the specific use case (e.g., `CreateProduct`) | String |
| `--usecase-type` | `-ut` | The type of MediatR request | `command` or `query` |
| `--entity` | `-e` | The primary Aggregate/Entity the slice operates on (e.g., `Product`) | String |
| `--output` | `-o` | Target directory for the feature folder | Path (default: `src/Web/Features`) |

### Generated Artifacts

When running:
```bash
scaffold-feature --name CreateOrder --usecase-type command --entity Order
```

The tool creates the following structure under `src/Features/Order`:

| File Name | Purpose | Location |
|-----------|---------|----------|
| `CreateOrderCommand` | Defines the command request, its handler, and validation logic | `Features/Order/` |
| `CreateOrderEndpoint` | Defines the API route/endpoint that maps to the `CreateOrderCommand` | `Features/Order/` |
| `Order` | **(Conditional)** If the Entity file doesn't exist in `src/Domain/`, creates a placeholder aggregate root requiring the developer to fill in the invariants | `Domain/` |
| `OrderCreatedEvent` | **(Conditional)** A placeholder for a related Domain Event | `Domain/` |

**Goal:** Provide a fully functioning, compile-ready feature slice immediately upon execution, minimizing boilerplate.

---

## 3. Migration Guide: From Layered to Hybrid VSA

This guide outlines the process of migrating a solution built on a multi-project layered architecture to the Hybrid VSA Modular Monolith.

### Phase 1: Project Consolidation

1. **Delete Projects:** Remove the separate `Application` and `Infrastructure` modules/projects
2. **Move Code:** Move all code from the old `Application` and `Infrastructure` modules into the main application module
3. **Refactor Namespaces/Packages:** Update all namespaces/packages from `MyProject.Application` and `MyProject.Infrastructure` to the consolidated structure
4. **Preserve Domain:** Keep the `Domain` module/package separate. It is the **Strict Core** and should remain isolated from all other concerns

### Phase 2: Vertical Slice Organization

1. **Create Root Folders:** In the `Web` project, create two root folders: `Features` and `Infrastructure`
2. **Move Infrastructure:** Place `ApplicationDbContext`, migrations, and any external service implementations (e.g., `EmailSender`) into the new `Infrastructure` folder
3. **Create Feature Folders:** For every use case (Command/Query), create a folder under `Features` (e.g., `Features/Orders`)
4. **Group Files:** Move the related Command DTO, Command Handler, Validator, and any associated Mappers/DTOs into the new feature folder

### Phase 3: Dependency Refactoring & Command/Query Pipeline

1. **Simplify Data Access:** 
   - Review Handler constructors
   - If a Handler was previously injected with a `Repository`, consider injecting the database context directly for simplicity, as per the pragmatic VSA approach

2. **Configure Command/Query Mediator (Crucial Step):**
   - In your application startup/configuration, ensure the mediator pattern implementation is configured to discover:
     - **Handlers:** From the consolidated module/assembly
     - **Behaviors/Middleware:** Explicitly register validation and transaction behaviors to handle the Unit of Work and Domain Event dispatching centrally, replacing explicit transaction calls in individual handlers

3. **Remove Repositories (Optional):**
   - If a repository was only being used for simple CRUD, delete the repository interface and implementation
   - Use the database context directly in the handler
   - If the repository contains complex logic (e.g., using the Specification Pattern), keep it in the `Infrastructure` folder and refactor it into a lightweight Query Service

---

## 4. Building the API (CI/CD Setup)

To use automated CI/CD platforms (GitHub Actions, GitLab CI, Jenkins, CircleCI, etc.) to build and deploy this API, define a workflow that executes the following steps:

### Build Pipeline Steps

1. **Checkout Code:** Get the latest version of the repository
2. **Restore Dependencies:** Download necessary packages/dependencies (npm install, pip install, go mod download, etc.)
3. **Build Solution:** Compile/build the entire solution
4. **Run Tests:** Execute unit and integration tests
   - The strict Domain core ensures unit tests are fast and reliable
5. **Publish Artifacts:** Create the deployable application bundle (Docker image, JAR, binary, etc.)
6. **Deploy:** Push the artifacts to the target environment (container registry, Kubernetes, cloud platform, VM, etc.)

### Example: CI/CD Pipeline Structure

This structure provides a robust build pipeline suitable for this modular monolith.

**Key Pipeline Stages:**

1. **Source Control Integration**
   - Trigger on commits to main branch
   - Trigger on pull/merge requests

2. **Build Environment Setup**
   - Configure runtime environment (language version, dependencies)
   - Set environment variables

3. **Dependency Management**
   - Restore/install project dependencies
   - Cache dependencies for faster builds

4. **Compilation/Build**
   - Compile source code
   - Build application artifacts

5. **Testing**
   - Run unit tests
   - Run integration tests
   - Generate code coverage reports

6. **Artifact Creation**
   - Package application for deployment
   - Create Docker images (if containerized)
   - Version artifacts appropriately

7. **Deployment Preparation**
   - Store artifacts in registry/repository
   - Tag releases
   - Prepare deployment manifests

This workflow ensures that every code change is validated by tests before being bundled for deployment, creating a high-quality build process.

---

## 5. Key Benefits

### Developer Experience
- **Minimal boilerplate** with CLI template
- **Feature isolation** - all related code in one folder
- **Fast feedback** - strict domain enables rapid unit testing

### Architecture
- **Single deployable unit** - simplified deployment
- **Clear boundaries** - domain core remains pure
- **Pragmatic** - repositories only when needed

### Performance
- **Direct EF Core queries** in handlers for simple cases
- **Specification pattern** available for complex queries
- **Transactional consistency** via MediatR behaviors

---

## 6. Project Structure

```
src/
├── Application/
│   ├── Domain/              # Strict domain core (separate module)
│   │   ├── Entities/
│   │   ├── ValueObjects/
│   │   └── Events/
│   ├── Features/            # Vertical slices
│   │   ├── Orders/
│   │   │   ├── CreateOrder/
│   │   │   │   ├── CreateOrderCommand
│   │   │   │   ├── CreateOrderEndpoint
│   │   │   │   └── CreateOrderValidator
│   │   │   └── GetOrder/
│   │   └── Products/
│   ├── Infrastructure/      # Cross-cutting concerns
│   │   ├── Data/
│   │   │   ├── DatabaseContext
│   │   │   └── Migrations/
│   │   └── Services/
│   └── Main (entry point)
└── tests/
    ├── UnitTests/
    └── IntegrationTests/
```

---

## 7. Next Steps

1. **Create scaffolding tool** - Build the feature scaffolding CLI tool for your chosen language/framework
2. **Set up CI/CD** - Configure your preferred CI/CD platform (GitHub Actions, GitLab CI, Jenkins, etc.)
3. **Migrate existing features** - Follow the 3-phase migration guide
4. **Add new features** - Use the scaffolding tool for consistency
5. **Monitor and optimize** - Leverage observability tools (Prometheus, Grafana, ELK stack, or cloud-native monitoring)

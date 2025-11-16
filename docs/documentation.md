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

## 2. CLI Tool Specification: `dotnet new ca-slice`

To achieve high feature velocity, a custom .NET CLI template automates the creation of new Vertical Slices (Features).

### Command Syntax

```bash
dotnet new ca-slice --name <FeatureName> --usecase-type <Type> --entity <EntityName>

# Example:
dotnet new ca-slice -n CreateProduct -ut command -e Product
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
dotnet new ca-slice --name CreateOrder --usecase-type command --entity Order
```

The tool creates the following structure under `src/Web/Features/Order`:

| File Name | Purpose | Location |
|-----------|---------|----------|
| `CreateOrderCommand.cs` | Defines the `IRequest<TResponse>`, its Handler (`IRequestHandler`), and the corresponding FluentValidation `AbstractValidator` | `Features/Order/` |
| `CreateOrderEndpoint.cs` | Defines the minimal API or FastEndpoints route that maps to the `CreateOrderCommand` | `Features/Order/` |
| `Order.cs` | **(Conditional)** If the Entity file doesn't exist in `src/Web/Domain/`, creates a placeholder aggregate root requiring the developer to fill in the invariants | `Domain/` |
| `OrderCreatedEvent.cs` | **(Conditional)** A placeholder for a related Domain Event | `Domain/` |

**Goal:** Provide a fully functioning, compile-ready feature slice immediately upon execution, minimizing boilerplate.

---

## 3. Migration Guide: From Layered to Hybrid VSA

This guide outlines the process of migrating a solution built on a multi-project layered template (e.g., Ardalis Full or Jason Taylor) to the Hybrid VSA Modular Monolith.

### Phase 1: Project Consolidation

1. **Delete Projects:** Remove the `Application` and `Infrastructure` project files (`.csproj`)
2. **Move Code:** Move all C# files from the old `Application` and `Infrastructure` projects into the main `Web` project
3. **Refactor Namespaces:** Update all namespaces from `MyProject.Application` and `MyProject.Infrastructure` to the single `MyProject.Web` namespace
4. **Preserve Domain:** Keep the `Domain` project/namespace separate. It is the **Strict Core** and should remain isolated from all other concerns

### Phase 2: Vertical Slice Organization

1. **Create Root Folders:** In the `Web` project, create two root folders: `Features` and `Infrastructure`
2. **Move Infrastructure:** Place `ApplicationDbContext`, migrations, and any external service implementations (e.g., `EmailSender`) into the new `Infrastructure` folder
3. **Create Feature Folders:** For every use case (Command/Query), create a folder under `Features` (e.g., `Features/Orders`)
4. **Group Files:** Move the related Command DTO, Command Handler, Validator, and any associated Mappers/DTOs into the new feature folder

### Phase 3: Dependency Refactoring & MediatR Pipeline

1. **Simplify Data Access:** 
   - Review Handler constructors
   - If a Handler was previously injected with an `IRepository<T>`, change the injection to `IApplicationDbContext` (or a specific lightweight query service) for simplicity, as per the pragmatic VSA approach

2. **Configure MediatR (Crucial Step):**
   - In `Program.cs`, ensure MediatR is configured to discover:
     - **Handlers:** From the consolidated assembly
       ```csharp
       services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(assembly));
       ```
     - **Behaviors:** Explicitly register the `ValidationBehavior` (FluentValidation) and the `TransactionBehavior` to handle the Unit of Work and Domain Event dispatching centrally, replacing explicit `_context.BeginTransaction()` calls in individual handlers

3. **Remove Repositories (Optional):**
   - If a full `IRepository` was only being used for simple CRUD, delete the repository interface and implementation
   - Use `IApplicationDbContext` directly in the handler
   - If the repository contains complex logic (e.g., using the Specification Pattern), keep it in the `Infrastructure` folder and refactor it into a lightweight Query Service

---

## 4. Building the API (CI/CD Setup)

To use an automated tool like Google Joules or standard CI/CD platforms (GitHub Actions, Azure DevOps) to build and deploy this API, define a workflow that executes the following steps:

### Build Pipeline Steps

1. **Checkout Code:** Get the latest version of the repository
2. **Restore Dependencies:** Run `dotnet restore` to download necessary NuGet packages
3. **Build Solution:** Run `dotnet build --configuration Release` to compile the entire solution
4. **Run Tests:** Run `dotnet test --configuration Release --no-build` to execute unit and integration tests
   - The strict Domain core ensures unit tests are fast and reliable
5. **Publish Artifacts:** Run `dotnet publish -c Release -o app/publish` to create the deployable application bundle
6. **Deploy:** Utilize the deployment tool (azd, Azure DevOps, or others) to push the published artifacts to the target environment (e.g., Azure App Service or Kubernetes)

### Example: GitHub Actions Workflow

This structure provides a robust build pipeline suitable for this modular monolith.

```yaml
name: .NET Core CI/CD

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '10.0.x'
    
    # 1. Restore Dependencies
    - name: Restore dependencies
      run: dotnet restore
    
    # 2. Build Solution
    - name: Build
      run: dotnet build --configuration Release --no-restore
    
    # 3. Run Unit and Integration Tests
    - name: Test
      run: dotnet test --configuration Release --no-build
      # Assuming test projects are correctly named and located
      
    # 4. Publish Artifacts (Creates the deployable output)
    - name: Publish
      run: dotnet publish src/MyProject.Web/MyProject.Web.csproj -c Release -o release_output
      
    # 5. Upload for Deployment (Deployment step is usually separate)
    - name: Upload artifact for deployment
      uses: actions/upload-artifact@v4
      with:
        name: web-app-package
        path: release_output
```

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
├── MyProject.Web/
│   ├── Domain/              # Strict domain core (separate project)
│   │   ├── Entities/
│   │   ├── ValueObjects/
│   │   └── Events/
│   ├── Features/            # Vertical slices
│   │   ├── Orders/
│   │   │   ├── CreateOrder/
│   │   │   │   ├── CreateOrderCommand.cs
│   │   │   │   ├── CreateOrderEndpoint.cs
│   │   │   │   └── CreateOrderValidator.cs
│   │   │   └── GetOrder/
│   │   └── Products/
│   ├── Infrastructure/      # Cross-cutting concerns
│   │   ├── Data/
│   │   │   ├── ApplicationDbContext.cs
│   │   │   └── Migrations/
│   │   └── Services/
│   └── Program.cs
└── tests/
    ├── UnitTests/
    └── IntegrationTests/
```

---

## 7. Next Steps

1. **Install CLI template** - Create the `dotnet new ca-slice` template
2. **Set up CI/CD** - Configure GitHub Actions or Azure DevOps
3. **Migrate existing features** - Follow the 3-phase migration guide
4. **Add new features** - Use the CLI tool for consistency
5. **Monitor and optimize** - Leverage Application Insights or similar tools

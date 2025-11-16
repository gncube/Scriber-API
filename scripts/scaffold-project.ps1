# Scriber API - Project Scaffolding Script
# This script creates the complete solution structure following Clean Architecture + DDD principles

param(
    [string]$SolutionName = "Scriber",
    [string]$RootPath = "src"
)

Write-Host "🚀 Scaffolding Scriber API Solution..." -ForegroundColor Green
Write-Host ""

# Create root directory
$solutionRoot = Join-Path $PSScriptRoot ".." $RootPath
New-Item -ItemType Directory -Force -Path $solutionRoot | Out-Null

Set-Location $solutionRoot

# Create solution file
Write-Host "📦 Creating solution file..." -ForegroundColor Cyan
dotnet new sln -n $SolutionName

# Define projects
$projects = @(
    @{
        Name = "$SolutionName.Domain"
        Type = "classlib"
        Folder = "Core"
        Description = "Domain layer - Entities, Value Objects, Domain Events"
    },
    @{
        Name = "$SolutionName.Application"
        Type = "classlib"
        Folder = "Core"
        Description = "Application layer - Use Cases, Commands, Queries, DTOs"
    },
    @{
        Name = "$SolutionName.Infrastructure"
        Type = "classlib"
        Folder = "Infrastructure"
        Description = "Infrastructure layer - EF Core, External Services, Persistence"
    },
    @{
        Name = "$SolutionName.API"
        Type = "webapi"
        Folder = "Presentation"
        Description = "REST API - Controllers, Middleware, Configuration"
    },
    @{
        Name = "$SolutionName.UnitTests"
        Type = "xunit"
        Folder = "Tests"
        Description = "Unit tests for Domain and Application layers"
    },
    @{
        Name = "$SolutionName.IntegrationTests"
        Type = "xunit"
        Folder = "Tests"
        Description = "Integration tests for API and Infrastructure"
    }
)

# Create projects
Write-Host ""
Write-Host "📁 Creating projects..." -ForegroundColor Cyan
foreach ($project in $projects) {
    $projectPath = Join-Path $project.Folder $project.Name
    
    Write-Host "  ✓ Creating $($project.Name) ($($project.Type))..." -ForegroundColor Gray
    dotnet new $project.Type -n $project.Name -o $projectPath --framework net8.0
    
    # Add project to solution
    dotnet sln add $projectPath
}

Write-Host ""
Write-Host "📦 Adding NuGet packages..." -ForegroundColor Cyan

# Domain layer packages (minimal dependencies)
Write-Host "  → Domain layer..." -ForegroundColor Gray
# No external dependencies - pure domain logic

# Application layer packages
Write-Host "  → Application layer..." -ForegroundColor Gray
dotnet add "Core/$SolutionName.Application" package FluentValidation --version 11.9.0
dotnet add "Core/$SolutionName.Application" package FluentValidation.DependencyInjectionExtensions --version 11.9.0

# Infrastructure layer packages
Write-Host "  → Infrastructure layer..." -ForegroundColor Gray
dotnet add "Infrastructure/$SolutionName.Infrastructure" package Microsoft.EntityFrameworkCore --version 8.0.0
dotnet add "Infrastructure/$SolutionName.Infrastructure" package Npgsql.EntityFrameworkCore.PostgreSQL --version 8.0.0
dotnet add "Infrastructure/$SolutionName.Infrastructure" package EFCore.NamingConventions --version 8.0.0
dotnet add "Infrastructure/$SolutionName.Infrastructure" package Microsoft.EntityFrameworkCore.Design --version 8.0.0
dotnet add "Infrastructure/$SolutionName.Infrastructure" package Stripe.net --version 44.0.0
dotnet add "Infrastructure/$SolutionName.Infrastructure" package SendGrid --version 9.29.3
dotnet add "Infrastructure/$SolutionName.Infrastructure" package Azure.Storage.Blobs --version 12.19.1

# API layer packages
Write-Host "  → API layer..." -ForegroundColor Gray
dotnet add "Presentation/$SolutionName.API" package Microsoft.AspNetCore.Authentication.JwtBearer --version 8.0.0
dotnet add "Presentation/$SolutionName.API" package Swashbuckle.AspNetCore --version 6.5.0
dotnet add "Presentation/$SolutionName.API" package Serilog.AspNetCore --version 8.0.0
dotnet add "Presentation/$SolutionName.API" package Serilog.Sinks.Console --version 5.0.1
dotnet add "Presentation/$SolutionName.API" package AspNetCore.HealthChecks.NpgSql --version 8.0.0

# Test projects packages
Write-Host "  → Test projects..." -ForegroundColor Gray
dotnet add "Tests/$SolutionName.UnitTests" package FluentAssertions --version 6.12.0
dotnet add "Tests/$SolutionName.UnitTests" package NSubstitute --version 5.1.0
dotnet add "Tests/$SolutionName.UnitTests" package xunit --version 2.6.2
dotnet add "Tests/$SolutionName.UnitTests" package xunit.runner.visualstudio --version 2.5.4
dotnet add "Tests/$SolutionName.UnitTests" package coverlet.collector --version 6.0.0

dotnet add "Tests/$SolutionName.IntegrationTests" package FluentAssertions --version 6.12.0
dotnet add "Tests/$SolutionName.IntegrationTests" package Microsoft.AspNetCore.Mvc.Testing --version 8.0.0
dotnet add "Tests/$SolutionName.IntegrationTests" package Testcontainers.PostgreSql --version 3.7.0
dotnet add "Tests/$SolutionName.IntegrationTests" package xunit --version 2.6.2

# Add project references
Write-Host ""
Write-Host "🔗 Adding project references..." -ForegroundColor Cyan

# Application references Domain
dotnet add "Core/$SolutionName.Application" reference "Core/$SolutionName.Domain"

# Infrastructure references Application and Domain
dotnet add "Infrastructure/$SolutionName.Infrastructure" reference "Core/$SolutionName.Application"
dotnet add "Infrastructure/$SolutionName.Infrastructure" reference "Core/$SolutionName.Domain"

# API references all layers
dotnet add "Presentation/$SolutionName.API" reference "Core/$SolutionName.Application"
dotnet add "Presentation/$SolutionName.API" reference "Infrastructure/$SolutionName.Infrastructure"

# Tests reference appropriate layers
dotnet add "Tests/$SolutionName.UnitTests" reference "Core/$SolutionName.Domain"
dotnet add "Tests/$SolutionName.UnitTests" reference "Core/$SolutionName.Application"

dotnet add "Tests/$SolutionName.IntegrationTests" reference "Presentation/$SolutionName.API"
dotnet add "Tests/$SolutionName.IntegrationTests" reference "Infrastructure/$SolutionName.Infrastructure"

Write-Host ""
Write-Host "📂 Creating folder structure..." -ForegroundColor Cyan

# Domain layer folders
$domainFolders = @(
    "SeedWork",
    "Publishing/Entities",
    "Publishing/ValueObjects",
    "Publishing/Events",
    "Publishing/Exceptions",
    "Subscriptions/Entities",
    "Subscriptions/ValueObjects",
    "Subscriptions/Events",
    "Payments/Entities",
    "Payments/ValueObjects",
    "Payments/Events"
)

foreach ($folder in $domainFolders) {
    New-Item -ItemType Directory -Force -Path "Core/$SolutionName.Domain/$folder" | Out-Null
}

# Application layer folders
$applicationFolders = @(
    "Common/Messaging",
    "Common/Behaviors",
    "Common/Exceptions",
    "Common/Interfaces",
    "Common/Models",
    "Publishing/Commands/CreatePost",
    "Publishing/Commands/PublishPost",
    "Publishing/Commands/UpdatePost",
    "Publishing/Commands/SchedulePost",
    "Publishing/Queries/GetPost",
    "Publishing/Queries/GetPostList",
    "Publishing/Queries/SearchPosts",
    "Publishing/EventHandlers",
    "Publishing/DTOs",
    "Subscriptions/Commands/Subscribe",
    "Subscriptions/Commands/CancelSubscription",
    "Subscriptions/Commands/ChangeTier",
    "Subscriptions/Queries",
    "Subscriptions/EventHandlers",
    "Subscriptions/DTOs"
)

foreach ($folder in $applicationFolders) {
    New-Item -ItemType Directory -Force -Path "Core/$SolutionName.Application/$folder" | Out-Null
}

# Infrastructure layer folders
$infrastructureFolders = @(
    "Persistence/Contexts",
    "Persistence/Configurations/Publishing",
    "Persistence/Configurations/Subscriptions",
    "Persistence/Configurations/Payments",
    "Persistence/Repositories",
    "Persistence/Migrations",
    "Messaging",
    "Services",
    "Identity",
    "Extensions"
)

foreach ($folder in $infrastructureFolders) {
    New-Item -ItemType Directory -Force -Path "Infrastructure/$SolutionName.Infrastructure/$folder" | Out-Null
}

# API layer folders
$apiFolders = @(
    "Controllers",
    "Filters",
    "Middleware",
    "Extensions"
)

foreach ($folder in $apiFolders) {
    New-Item -ItemType Directory -Force -Path "Presentation/$SolutionName.API/$folder" | Out-Null
}

Write-Host ""
Write-Host "📝 Creating base files..." -ForegroundColor Cyan

# Create Domain SeedWork base classes
$entityContent = @'
namespace Scriber.Domain.SeedWork;

public abstract class Entity<TId> where TId : notnull
{
    public TId Id { get; protected set; } = default!;

    public override bool Equals(object? obj)
    {
        if (obj is not Entity<TId> other)
            return false;

        if (ReferenceEquals(this, other))
            return true;

        if (GetType() != other.GetType())
            return false;

        return Id.Equals(other.Id);
    }

    public override int GetHashCode() => Id.GetHashCode();

    public static bool operator ==(Entity<TId>? left, Entity<TId>? right)
    {
        if (left is null && right is null) return true;
        if (left is null || right is null) return false;
        return left.Equals(right);
    }

    public static bool operator !=(Entity<TId>? left, Entity<TId>? right) => !(left == right);
}
'@

Set-Content -Path "Core/$SolutionName.Domain/SeedWork/Entity.cs" -Value $entityContent

$aggregateRootContent = @'
namespace Scriber.Domain.SeedWork;

using Scriber.Application.Common.Messaging;

public abstract class AggregateRoot<TId> : Entity<TId> where TId : notnull
{
    private readonly List<INotification> _domainEvents = new();

    public IReadOnlyCollection<INotification> DomainEvents => _domainEvents.AsReadOnly();

    protected void AddDomainEvent(INotification domainEvent)
    {
        _domainEvents.Add(domainEvent);
    }

    public void ClearDomainEvents()
    {
        _domainEvents.Clear();
    }
}
'@

Set-Content -Path "Core/$SolutionName.Domain/SeedWork/AggregateRoot.cs" -Value $aggregateRootContent

$domainExceptionContent = @'
namespace Scriber.Domain.SeedWork;

public class DomainException : Exception
{
    public DomainException(string message) : base(message) { }
    
    public DomainException(string message, Exception innerException) 
        : base(message, innerException) { }
}
'@

Set-Content -Path "Core/$SolutionName.Domain/SeedWork/DomainException.cs" -Value $domainExceptionContent

# Create Application Common files
$iMediatorContent = @'
namespace Scriber.Application.Common.Messaging;

public interface IMediator
{
    Task<TResponse> Send<TResponse>(
        IRequest<TResponse> request, 
        CancellationToken cancellationToken = default);

    Task Publish<TNotification>(
        TNotification notification, 
        CancellationToken cancellationToken = default)
        where TNotification : INotification;

    Task Publish(
        IEnumerable<INotification> notifications, 
        CancellationToken cancellationToken = default);
}

public interface IRequest<out TResponse> { }

public interface ICommand : IRequest<Unit> { }

public interface ICommand<out TResponse> : IRequest<TResponse> { }

public interface IQuery<out TResponse> : IRequest<TResponse> { }

public interface IRequestHandler<in TRequest, TResponse> 
    where TRequest : IRequest<TResponse>
{
    Task<TResponse> Handle(TRequest request, CancellationToken cancellationToken);
}

public interface ICommandHandler<in TCommand> : IRequestHandler<TCommand, Unit>
    where TCommand : ICommand
{ }

public interface ICommandHandler<in TCommand, TResponse> : IRequestHandler<TCommand, TResponse>
    where TCommand : ICommand<TResponse>
{ }

public interface IQueryHandler<in TQuery, TResponse> : IRequestHandler<TQuery, TResponse>
    where TQuery : IQuery<TResponse>
{ }

public interface INotification { }

public interface INotificationHandler<in TNotification>
    where TNotification : INotification
{
    Task Handle(TNotification notification, CancellationToken cancellationToken);
}

public readonly struct Unit
{
    public static readonly Unit Value = new();
}
'@

Set-Content -Path "Core/$SolutionName.Application/Common/Messaging/IMediator.cs" -Value $iMediatorContent

$dependencyInjectionContent = @'
namespace Scriber.Application;

using FluentValidation;
using Microsoft.Extensions.DependencyInjection;
using System.Reflection;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        var assembly = Assembly.GetExecutingAssembly();

        // Register validators
        services.AddValidatorsFromAssembly(assembly);

        // Mediator will be registered by infrastructure layer

        return services;
    }
}
'@

Set-Content -Path "Core/$SolutionName.Application/DependencyInjection.cs" -Value $dependencyInjectionContent

# Create .gitignore
$gitignoreContent = @'
## Visual Studio

# User-specific files
*.rsuser
*.suo
*.user
*.userosscache
*.sln.docstates

# Build results
[Dd]ebug/
[Dd]ebugPublic/
[Rr]elease/
[Rr]eleases/
x64/
x86/
[Aa][Rr][Mm]/
[Aa][Rr][Mm]64/
bld/
[Bb]in/
[Oo]bj/
[Ll]og/
[Ll]ogs/

# Visual Studio cache/options
.vs/

# NuGet Packages
*.nupkg
*.snupkg
**/packages/*

# Test Results
[Tt]est[Rr]esult*/
[Bb]uild[Ll]og.*
*.trx
*.coverage
*.coveragexml

# .NET Core
project.lock.json
project.fragment.lock.json
artifacts/

# Rider
.idea/
*.sln.iml

# User secrets
appsettings.Development.json
appsettings.*.json
!appsettings.json

# Database
*.db
*.db-shm
*.db-wal
'@

Set-Content -Path ".gitignore" -Value $gitignoreContent

# Create README
$readmeContent = @'
# Scriber API

Newsletter and content publishing platform built with Clean Architecture and Domain-Driven Design.

## Architecture

- **Domain Layer** (`Scriber.Domain`) - Pure domain logic, entities, value objects, domain events
- **Application Layer** (`Scriber.Application`) - Use cases, CQRS commands/queries, DTOs
- **Infrastructure Layer** (`Scriber.Infrastructure`) - EF Core, repositories, external services
- **API Layer** (`Scriber.API`) - REST endpoints, authentication, middleware

## Tech Stack

- .NET 8.0
- PostgreSQL with EF Core
- Custom Mediator (MediatR-compatible, zero licensing cost)
- FluentValidation
- JWT Authentication
- Stripe for payments
- SendGrid for emails
- Azure Blob Storage for media

## Getting Started

### Prerequisites

- .NET 8.0 SDK
- PostgreSQL 15+
- Azure Storage Emulator (Azurite) for local development

### Setup

1. Clone the repository
2. Update connection string in `appsettings.json`
3. Run migrations:
   ```bash
   dotnet ef database update --project src/Infrastructure/Scriber.Infrastructure --startup-project src/Presentation/Scriber.API
   ```
4. Run the API:
   ```bash
   dotnet run --project src/Presentation/Scriber.API
   ```
5. Open Swagger: `https://localhost:5001/swagger`

### Run Tests

```bash
dotnet test
```

## Project Structure

```
src/
├── Core/
│   ├── Scriber.Domain/           # Domain entities, value objects
│   └── Scriber.Application/      # CQRS commands, queries, DTOs
├── Infrastructure/
│   └── Scriber.Infrastructure/   # EF Core, repositories, services
├── Presentation/
│   └── Scriber.API/              # REST API controllers
└── Tests/
    ├── Scriber.UnitTests/        # Unit tests
    └── Scriber.IntegrationTests/ # Integration tests
```

## Design Documents

See `/docs` folder for complete specifications:
- SPEC-1: Overall architecture
- SPEC-2: DDD Bounded Contexts
- SPEC-2.2: Custom MediatR Implementation
- SPEC-3: Aggregate Design
- SPEC-4: Application Layer (CQRS)
- SPEC-5: Infrastructure Layer
- SPEC-6: API Contracts

## Frugal Innovation Approach

This project saves ~$1,500 over 3 years by:
- Using custom mediator instead of commercial MediatR license
- Single database with schemas instead of microservices (initially)
- Azure serverless services (auto-scale to zero)
- Open-source dependencies only

## License

MIT
'@

Set-Content -Path "README.md" -Value $readmeContent

Write-Host ""
Write-Host "✅ Project scaffolding complete!" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Solution structure:" -ForegroundColor Yellow
Write-Host "  $solutionRoot/" -ForegroundColor Gray
Write-Host "  ├── Core/" -ForegroundColor Gray
Write-Host "  │   ├── $SolutionName.Domain/" -ForegroundColor Gray
Write-Host "  │   └── $SolutionName.Application/" -ForegroundColor Gray
Write-Host "  ├── Infrastructure/" -ForegroundColor Gray
Write-Host "  │   └── $SolutionName.Infrastructure/" -ForegroundColor Gray
Write-Host "  ├── Presentation/" -ForegroundColor Gray
Write-Host "  │   └── $SolutionName.API/" -ForegroundColor Gray
Write-Host "  └── Tests/" -ForegroundColor Gray
Write-Host "      ├── $SolutionName.UnitTests/" -ForegroundColor Gray
Write-Host "      └── $SolutionName.IntegrationTests/" -ForegroundColor Gray
Write-Host ""
Write-Host "🚀 Next steps:" -ForegroundColor Yellow
Write-Host "  1. cd $solutionRoot" -ForegroundColor Gray
Write-Host "  2. dotnet build" -ForegroundColor Gray
Write-Host "  3. Implement domain entities from SPEC-3" -ForegroundColor Gray
Write-Host "  4. Implement EF Core configurations from SPEC-5" -ForegroundColor Gray
Write-Host "  5. Implement CQRS handlers from SPEC-4" -ForegroundColor Gray
Write-Host "  6. Implement API controllers from SPEC-6" -ForegroundColor Gray
Write-Host ""
Write-Host "📚 Documentation: See /docs folder for detailed specifications" -ForegroundColor Cyan
Write-Host ""

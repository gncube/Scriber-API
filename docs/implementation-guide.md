# Scriber API - Implementation Guide

## Overview

This guide walks you through implementing the Scriber API based on the specifications in this `/docs` folder.

---

## Prerequisites

- .NET 8.0 SDK
- PostgreSQL 15+ (or Docker for PostgreSQL)
- Azure Storage Emulator (Azurite) or Azure account
- Stripe test account (for payments)
- SendGrid account (for emails)
- Your favorite IDE (Visual Studio, Rider, or VS Code)

---

## Step 1: Run the Scaffolding Script

```powershell
# From the repository root
.\scripts\scaffold-project.ps1
```

This creates:
- Solution with 6 projects (Domain, Application, Infrastructure, API, 2 test projects)
- Folder structure following Clean Architecture
- NuGet packages installed
- Project references configured
- Base classes (Entity, AggregateRoot, IMediator)

---

## Step 2: Implement Custom Mediator

**Location:** `src/Infrastructure/Scriber.Infrastructure/Messaging/`

Copy the complete implementation from **SPEC-2.2**:

1. `Mediator.cs` - Core mediator implementation
2. `MediatorExtensions.cs` - DI registration extensions

**Files to create:**
- `Messaging/Mediator.cs`
- `Messaging/RequestHandlerDelegate.cs`
- `Extensions/MediatorExtensions.cs`

**Register in `DependencyInjection.cs`:**

```csharp
services.AddMediator(
    typeof(ApplicationAssemblyMarker).Assembly
);
```

---

## Step 3: Implement Domain Layer

**Reference:** SPEC-3 (Aggregate Design)

### 3.1 Publishing Context

**Location:** `src/Core/Scriber.Domain/Publishing/`

**Entities:**
- `Post.cs` - Aggregate root with business logic
- `Publication.cs`
- `Tag.cs`

**Value Objects:**
- `ValueObjects/PostId.cs`
- `ValueObjects/PostTitle.cs`
- `ValueObjects/Slug.cs`
- `ValueObjects/PostContent.cs`
- `ValueObjects/Excerpt.cs`
- `ValueObjects/PublicationId.cs`
- `ValueObjects/AuthorId.cs`
- `ValueObjects/TagId.cs`

**Enums:**
- `PostStatus.cs` (Draft, Scheduled, Published)
- `VisibilityTier.cs` (Public, FreeSubscriber, PaidSubscriber)

**Domain Events:**
- `Events/PostDraftedEvent.cs`
- `Events/PostPublishedEvent.cs`
- `Events/PostUpdatedEvent.cs`
- `Events/PostScheduledEvent.cs`
- `Events/PostUnpublishedEvent.cs`

### 3.2 Subscription Context

**Location:** `src/Core/Scriber.Domain/Subscriptions/`

**Entities:**
- `Subscription.cs` - Aggregate root
- `Subscriber.cs`
- `SubscriptionTier.cs`

**Value Objects:**
- `ValueObjects/SubscriptionId.cs`
- `ValueObjects/SubscriberId.cs`
- `ValueObjects/TierId.cs`
- `ValueObjects/TrialPeriod.cs`
- `ValueObjects/Money.cs`

**Enums:**
- `SubscriptionStatus.cs` (Active, PastDue, Canceled, Trialing)
- `BillingCycle.cs` (Monthly, Yearly)

**Domain Events:**
- `Events/SubscriptionActivatedEvent.cs`
- `Events/SubscriptionRenewedEvent.cs`
- `Events/SubscriptionCanceledEvent.cs`
- `Events/TrialStartedEvent.cs`
- `Events/TrialEndedEvent.cs`

### 3.3 Payment Context

**Location:** `src/Core/Scriber.Domain/Payments/`

**Entities:**
- `Payment.cs` - Aggregate root

**Value Objects:**
- `ValueObjects/PaymentId.cs`

**Enums:**
- `PaymentStatus.cs` (Pending, Succeeded, Failed, Refunded)
- `PaymentProvider.cs` (Stripe, PayPal)

**Domain Events:**
- `Events/PaymentSucceededEvent.cs`
- `Events/PaymentFailedEvent.cs`

---

## Step 4: Implement Application Layer

**Reference:** SPEC-4 (Application Layer)

### 4.1 Common Exceptions

**Location:** `src/Core/Scriber.Application/Common/Exceptions/`

```csharp
// NotFoundException.cs
// UnauthorizedException.cs
// ForbiddenException.cs
// ValidationException.cs
```

### 4.2 Common Interfaces

**Location:** `src/Core/Scriber.Application/Common/Interfaces/`

```csharp
// IPostRepository.cs
// ISubscriptionRepository.cs
// ISubscriberRepository.cs
// IPublishingDbContext.cs
// ICurrentUserService.cs
// IEmailService.cs
// IPaymentService.cs
// ISubscriptionService.cs
// IBlobStorageService.cs
```

### 4.3 Pipeline Behaviors

**Location:** `src/Core/Scriber.Application/Common/Behaviors/`

```csharp
// IPipelineBehavior.cs
// LoggingBehavior.cs
// ValidationBehavior.cs
// PerformanceBehavior.cs
// TransactionBehavior.cs
```

### 4.4 Publishing Commands

**Location:** `src/Core/Scriber.Application/Publishing/Commands/`

For each command, create 3 files:
1. `CreatePost/CreatePostCommand.cs` - Command DTO
2. `CreatePost/CreatePostCommandHandler.cs` - Handler logic
3. `CreatePost/CreatePostCommandValidator.cs` - FluentValidation rules

**Commands to implement:**
- `CreatePost/`
- `PublishPost/`
- `UpdatePost/`
- `SchedulePost/`
- `DeletePost/`

### 4.5 Publishing Queries

**Location:** `src/Core/Scriber.Application/Publishing/Queries/`

**Queries to implement:**
- `GetPost/GetPostBySlugQuery.cs`
- `GetPost/GetPostBySlugQueryHandler.cs`
- `GetPostList/GetPostListQuery.cs`
- `GetPostList/GetPostListQueryHandler.cs`
- `SearchPosts/SearchPostsQuery.cs`
- `SearchPosts/SearchPostsQueryHandler.cs`

### 4.6 Domain Event Handlers

**Location:** `src/Core/Scriber.Application/Publishing/EventHandlers/`

```csharp
// SendEmailOnPostPublishedHandler.cs
// UpdateSearchIndexHandler.cs (future)
```

### 4.7 DTOs

**Location:** `src/Core/Scriber.Application/Publishing/DTOs/`

```csharp
// PostDetailDto.cs
// PostSummaryDto.cs
// AuthorDto.cs
// TagDto.cs
```

### 4.8 Subscription Commands & Queries

**Location:** `src/Core/Scriber.Application/Subscriptions/`

Repeat the same pattern as Publishing context for:
- `Commands/Subscribe/`
- `Commands/CancelSubscription/`
- `Commands/ChangeTier/`
- `Queries/GetMySubscriptions/`

---

## Step 5: Implement Infrastructure Layer

**Reference:** SPEC-5 (Infrastructure Layer)

### 5.1 Base DbContext

**Location:** `src/Infrastructure/Scriber.Infrastructure/Persistence/`

```csharp
// BaseDbContext.cs - Dispatches domain events on SaveChanges
// UnitOfWork.cs - Transaction coordination
```

### 5.2 DbContext Implementations

**Location:** `src/Infrastructure/Scriber.Infrastructure/Persistence/Contexts/`

```csharp
// PublishingDbContext.cs
// SubscriptionDbContext.cs
// PaymentDbContext.cs
```

### 5.3 EF Core Entity Configurations

**Location:** `src/Infrastructure/Scriber.Infrastructure/Persistence/Configurations/`

For each entity, create a configuration class:

**Publishing:**
- `Publishing/PostConfiguration.cs`
- `Publishing/PublicationConfiguration.cs`
- `Publishing/TagConfiguration.cs`

**Subscriptions:**
- `Subscriptions/SubscriptionConfiguration.cs`
- `Subscriptions/SubscriberConfiguration.cs`
- `Subscriptions/SubscriptionTierConfiguration.cs`

**Key points:**
- Use `.HasConversion()` for value objects
- Use `.OwnsOne()` for embedded value objects
- Configure indexes for performance
- Set up relationships and cascade behavior

### 5.4 Repositories

**Location:** `src/Infrastructure/Scriber.Infrastructure/Persistence/Repositories/`

```csharp
// PostRepository.cs
// SubscriptionRepository.cs
// SubscriberRepository.cs
// PaymentRepository.cs
```

### 5.5 External Services

**Location:** `src/Infrastructure/Scriber.Infrastructure/Services/`

```csharp
// EmailService.cs - SendGrid integration
// PaymentService.cs - Stripe integration
// BlobStorageService.cs - Azure Blob Storage
```

### 5.6 Identity Services

**Location:** `src/Infrastructure/Scriber.Infrastructure/Identity/`

```csharp
// CurrentUserService.cs - Extract user from HttpContext
// JwtTokenService.cs - Generate/validate JWT tokens
```

### 5.7 Dependency Injection

**Location:** `src/Infrastructure/Scriber.Infrastructure/`

```csharp
// DependencyInjection.cs
```

Register:
- DbContexts
- Repositories
- Services
- Settings (Options pattern)

---

## Step 6: Create Database Migrations

```bash
# Install EF Core CLI tools (if not already)
dotnet tool install --global dotnet-ef

# Add initial migration
dotnet ef migrations add InitialCreate \
  --project src/Infrastructure/Scriber.Infrastructure \
  --startup-project src/Presentation/Scriber.API \
  --context PublishingDbContext \
  --output-dir Persistence/Migrations/Publishing

# Repeat for other contexts
dotnet ef migrations add InitialCreate \
  --project src/Infrastructure/Scriber.Infrastructure \
  --startup-project src/Presentation/Scriber.API \
  --context SubscriptionDbContext \
  --output-dir Persistence/Migrations/Subscriptions

# Update database
dotnet ef database update \
  --project src/Infrastructure/Scriber.Infrastructure \
  --startup-project src/Presentation/Scriber.API
```

---

## Step 7: Implement API Layer

**Reference:** SPEC-6 (API Contracts)

### 7.1 Controllers

**Location:** `src/Presentation/Scriber.API/Controllers/`

```csharp
// AuthController.cs
// PublicationsController.cs
// PostsController.cs
// SubscriptionsController.cs
// MediaController.cs
// WebhooksController.cs
```

### 7.2 Filters & Middleware

**Location:** `src/Presentation/Scriber.API/Filters/`

```csharp
// GlobalExceptionFilter.cs - Centralized error handling
```

### 7.3 Configuration

**Location:** `src/Presentation/Scriber.API/`

**Program.cs** - Configure:
- JWT authentication
- Swagger/OpenAPI
- CORS
- Rate limiting
- Health checks
- Logging (Serilog)

**appsettings.json:**

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=scriber;Username=postgres;Password=yourpassword"
  },
  "Jwt": {
    "Issuer": "https://api.scriber.com",
    "Audience": "https://api.scriber.com",
    "SecretKey": "your-256-bit-secret-key-change-in-production",
    "ExpiresInMinutes": 60
  },
  "Email": {
    "ApiKey": "SG.your-sendgrid-api-key",
    "FromEmail": "noreply@scriber.com",
    "FromName": "Scriber"
  },
  "Stripe": {
    "SecretKey": "sk_test_your-stripe-secret-key",
    "WebhookSecret": "whsec_your-webhook-secret"
  },
  "BlobStorage": {
    "ConnectionString": "UseDevelopmentStorage=true",
    "BlobEndpoint": "http://127.0.0.1:10000/devstoreaccount1"
  },
  "Cors": {
    "AllowedOrigins": ["http://localhost:3000"]
  }
}
```

---

## Step 8: Write Tests

### 8.1 Unit Tests

**Location:** `src/Tests/Scriber.UnitTests/`

**Domain tests:**
```
Domain/
├── Publishing/
│   └── PostTests.cs - Test domain logic (Publish, Schedule, etc.)
└── Subscriptions/
    └── SubscriptionTests.cs
```

**Application tests:**
```
Application/
├── Publishing/
│   └── CreatePostCommandHandlerTests.cs
└── Subscriptions/
    └── SubscribeCommandHandlerTests.cs
```

### 8.2 Integration Tests

**Location:** `src/Tests/Scriber.IntegrationTests/`

```csharp
// WebApplicationFactory setup
// Database seeding helpers
// API endpoint tests
```

**Example test:**

```csharp
public class PostsControllerTests : IClassFixture<WebApplicationFactory<Program>>
{
    [Fact]
    public async Task CreatePost_ValidRequest_ReturnsCreatedPost()
    {
        // Arrange
        var client = _factory.CreateClient();
        var command = new CreatePostRequest(...);

        // Act
        var response = await client.PostAsJsonAsync("/api/v1/posts", command);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Created);
    }
}
```

---

## Step 9: Local Development Setup

### 9.1 Start PostgreSQL (Docker)

```bash
docker run --name scriber-postgres \
  -e POSTGRES_PASSWORD=yourpassword \
  -e POSTGRES_DB=scriber \
  -p 5432:5432 \
  -d postgres:15
```

### 9.2 Start Azurite (Azure Storage Emulator)

```bash
docker run -p 10000:10000 -p 10001:10001 -p 10002:10002 \
  mcr.microsoft.com/azure-storage/azurite
```

### 9.3 Run Migrations

```bash
dotnet ef database update \
  --project src/Infrastructure/Scriber.Infrastructure \
  --startup-project src/Presentation/Scriber.API
```

### 9.4 Run the API

```bash
dotnet run --project src/Presentation/Scriber.API
```

Open browser: `https://localhost:5001/swagger`

---

## Step 10: Verify Implementation

### Checklist

- [ ] Solution builds without errors
- [ ] All tests pass
- [ ] Swagger UI loads and shows all endpoints
- [ ] Can register a new user
- [ ] Can login and receive JWT token
- [ ] Can create a draft post (authenticated)
- [ ] Can publish a post
- [ ] Can retrieve published posts (public endpoint)
- [ ] Paywall enforcement works (free vs paid content)
- [ ] Can subscribe to a publication
- [ ] Stripe webhook processes payments
- [ ] SendGrid sends emails on post publish
- [ ] Database migrations apply successfully

---

## Development Workflow

### 1. Feature Implementation

```bash
# 1. Create feature branch
git checkout -b feature/add-post-comments

# 2. Implement domain logic (SPEC-3)
# 3. Add application layer (SPEC-4)
# 4. Update infrastructure (SPEC-5)
# 5. Add API endpoint (SPEC-6)
# 6. Write tests
# 7. Run tests
dotnet test

# 8. Commit and push
git commit -m "feat: add post comments"
git push origin feature/add-post-comments
```

### 2. Database Changes

```bash
# Add migration
dotnet ef migrations add AddCommentSupport \
  --project src/Infrastructure/Scriber.Infrastructure \
  --startup-project src/Presentation/Scriber.API

# Review generated migration
# Apply to database
dotnet ef database update
```

### 3. Running Tests

```bash
# Run all tests
dotnet test

# Run with coverage
dotnet test /p:CollectCoverage=true

# Run specific test
dotnet test --filter "FullyQualifiedName~PostTests"
```

---

## Production Deployment (Azure)

### Prerequisites

- Azure subscription
- Azure CLI installed
- Bicep templates (create separately or use Azure Portal)

### Resources to Create

1. **Azure Container Apps** - API hosting
2. **Azure Database for PostgreSQL (Flexible Server)** - Database
3. **Azure Blob Storage** - Media files
4. **Azure CDN** - Media delivery
5. **Azure Application Insights** - Monitoring
6. **Azure Key Vault** - Secrets management

### Deployment Steps

```bash
# Login to Azure
az login

# Build and push Docker image
docker build -t scriber-api:latest .
docker tag scriber-api:latest yourregistry.azurecr.io/scriber-api:latest
docker push yourregistry.azurecr.io/scriber-api:latest

# Deploy to Container Apps
az containerapp update \
  --name scriber-api \
  --resource-group scriber-rg \
  --image yourregistry.azurecr.io/scriber-api:latest
```

---

## Troubleshooting

### Common Issues

**Issue:** "No service for type 'IMediator' has been registered"
- **Solution:** Ensure `AddMediator()` is called in Infrastructure DI setup

**Issue:** EF Core migrations fail
- **Solution:** Check connection string, ensure PostgreSQL is running

**Issue:** JWT authentication fails
- **Solution:** Verify JWT secret key matches in appsettings.json

**Issue:** Stripe webhook signature invalid
- **Solution:** Use correct webhook secret from Stripe dashboard

---

## Next Steps

1. Implement remaining bounded contexts (Media, Notifications)
2. Add background jobs (Azure Functions) for scheduled posts
3. Implement analytics tracking
4. Add caching layer (Redis)
5. Set up CI/CD pipeline (GitHub Actions)
6. Configure monitoring and alerts

---

## Resources

- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [Domain-Driven Design](https://martinfowler.com/bliki/DomainDrivenDesign.html)
- [EF Core Documentation](https://docs.microsoft.com/ef/core/)
- [ASP.NET Core Documentation](https://docs.microsoft.com/aspnet/core/)
- [Stripe API Reference](https://stripe.com/docs/api)

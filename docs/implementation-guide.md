# Scriber API - Implementation Guide

## Overview

This guide walks you through implementing the Scriber API based on the specifications in this `/docs` folder.

---

## Prerequisites

- Runtime environment for your chosen language (Node.js, Python, Go, Java, .NET, etc.)
- Relational database (PostgreSQL 15+, MySQL 8+, or equivalent)
- Object storage (S3-compatible, local filesystem, or cloud storage)
- Payment provider test account (Stripe, PayPal, or equivalent)
- Email service account (SendGrid, Mailgun, SES, or equivalent)
- Your favorite IDE/editor

---

## Step 1: Run the Scaffolding Script

```bash
# From the repository root
./scripts/scaffold-project.sh  # or .ps1 for Windows
```

This creates:
- Project structure with separate modules (Domain, Application, Infrastructure, API, Tests)
- Folder structure following Clean Architecture
- Dependencies installed
- Module references configured
- Base classes/interfaces (Entity, AggregateRoot, Mediator)

---

## Step 2: Implement Command/Query Mediator

**Location:** `src/Infrastructure/Messaging/`

Implement a mediator pattern or use an existing library for your language:

**Files to create:**
- `Messaging/Mediator` - Core mediator implementation
- `Messaging/RequestHandler` - Handler interface/base class
- `Extensions/MediatorRegistration` - Dependency injection setup

**Register in your DI container:**
- Scan and register all command/query handlers
- Register pipeline behaviors (validation, logging, transactions)
- Configure mediator as singleton or scoped service
```

---

## Step 3: Implement Domain Layer

**Reference:** SPEC-3 (Aggregate Design)

### 3.1 Publishing Context

**Location:** `src/Domain/Publishing/`

**Entities:**
- `Post` - Aggregate root with business logic
- `Publication`
- `Tag`

**Value Objects:**
- `ValueObjects/PostId`
- `ValueObjects/PostTitle`
- `ValueObjects/Slug`
- `ValueObjects/PostContent`
- `ValueObjects/Excerpt`
- `ValueObjects/PublicationId`
- `ValueObjects/AuthorId`
- `ValueObjects/TagId`

**Enums/Constants:**
- `PostStatus` (Draft, Scheduled, Published)
- `VisibilityTier` (Public, FreeSubscriber, PaidSubscriber)

**Domain Events:**
- `Events/PostDraftedEvent`
- `Events/PostPublishedEvent`
- `Events/PostUpdatedEvent`
- `Events/PostScheduledEvent`
- `Events/PostUnpublishedEvent`

### 3.2 Subscription Context

**Location:** `src/Domain/Subscriptions/`

**Entities:**
- `Subscription` - Aggregate root
- `Subscriber`
- `SubscriptionTier`

**Value Objects:**
- `ValueObjects/SubscriptionId`
- `ValueObjects/SubscriberId`
- `ValueObjects/TierId`
- `ValueObjects/TrialPeriod`
- `ValueObjects/Money`

**Enums/Constants:**
- `SubscriptionStatus` (Active, PastDue, Canceled, Trialing)
- `BillingCycle` (Monthly, Yearly)

**Domain Events:**
- `Events/SubscriptionActivatedEvent.cs`
- `Events/SubscriptionRenewedEvent.cs`
- `Events/SubscriptionCanceledEvent.cs`
- `Events/TrialStartedEvent.cs`
- `Events/TrialEndedEvent.cs`

### 3.3 Payment Context

**Location:** `src/Domain/Payments/`

**Entities:**
- `Payment` - Aggregate root

**Value Objects:**
- `ValueObjects/PaymentId`

**Enums/Constants:**
- `PaymentStatus` (Pending, Succeeded, Failed, Refunded)
- `PaymentProvider` (Stripe, PayPal, etc.)

**Domain Events:**
- `Events/PaymentSucceededEvent.cs`
- `Events/PaymentFailedEvent.cs`

---

## Step 4: Implement Application Layer

**Reference:** SPEC-4 (Application Layer)

### 4.1 Common Exceptions

**Location:** `src/Application/Common/Exceptions/`

- `NotFoundException`
- `UnauthorizedException`
- `ForbiddenException`
- `ValidationException`

### 4.2 Common Interfaces

**Location:** `src/Application/Common/Interfaces/`

- `IPostRepository`
- `ISubscriptionRepository`
- `ISubscriberRepository`
- `IDatabaseContext`
- `ICurrentUserService`
- `IEmailService`
- `IPaymentService`
- `ISubscriptionService`
- `IObjectStorageService`

### 4.3 Pipeline Behaviors/Middleware

**Location:** `src/Application/Common/Behaviors/`

- `IPipelineBehavior` (interface/base class)
- `LoggingBehavior`
- `ValidationBehavior`
- `PerformanceBehavior`
- `TransactionBehavior`

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

Use your ORM's migration tool to create and apply database migrations:

**Examples by ORM:**

```bash
# Entity Framework Core (.NET)
dotnet ef migrations add InitialCreate
dotnet ef database update

# TypeORM (TypeScript/Node.js)
npm run typeorm migration:generate -- -n InitialCreate
npm run typeorm migration:run

# Alembic (Python/SQLAlchemy)
alembic revision --autogenerate -m "Initial create"
alembic upgrade head

# Flyway (Java/JVM)
flyway migrate

# Liquibase (Java/JVM)
liquibase update
```

---

## Step 7: Implement API Layer

**Reference:** SPEC-6 (API Contracts)

### 7.1 API Endpoints/Controllers

**Location:** `src/API/Controllers/` or `src/API/Routes/`

- `AuthController` / `auth.routes`
- `PublicationsController` / `publications.routes`
- `PostsController` / `posts.routes`
- `SubscriptionsController` / `subscriptions.routes`
- `MediaController` / `media.routes`
- `WebhooksController` / `webhooks.routes`

### 7.2 Middleware & Error Handling

**Location:** `src/API/Middleware/`

- `GlobalExceptionHandler` - Centralized error handling
- `RequestLoggingMiddleware` - Request/response logging
- `AuthenticationMiddleware` - JWT validation

### 7.3 Configuration

**Location:** `src/API/`

**Application entry point** - Configure:
- JWT authentication
- API documentation (Swagger/OpenAPI)
- CORS
- Rate limiting
- Health checks
- Logging

**Configuration file (JSON/YAML/ENV):**

```yaml
Database:
  ConnectionString: "postgresql://localhost:5432/scriber"
  # or: "mysql://localhost:3306/scriber"
  # or: "mongodb://localhost:27017/scriber"

JWT:
  Issuer: "https://api.scriber.com"
  Audience: "https://api.scriber.com"
  SecretKey: "your-256-bit-secret-key-change-in-production"
  ExpiresInMinutes: 60

Email:
  Provider: "sendgrid"  # or "mailgun", "ses", etc.
  ApiKey: "your-email-provider-api-key"
  FromEmail: "noreply@scriber.com"
  FromName: "Scriber"

Payments:
  Provider: "stripe"  # or "paypal", "square", etc.
  SecretKey: "your-payment-provider-secret-key"
  WebhookSecret: "your-webhook-secret"

ObjectStorage:
  Provider: "s3"  # or "minio", "gcs", "azure", etc.
  Endpoint: "http://localhost:9000"
  AccessKey: "your-access-key"
  SecretKey: "your-secret-key"
  BucketName: "scriber-media"

CORS:
  AllowedOrigins:
    - "http://localhost:3000"
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

### 9.1 Start Database (Docker)

```bash
# PostgreSQL
docker run --name scriber-db \
  -e POSTGRES_PASSWORD=yourpassword \
  -e POSTGRES_DB=scriber \
  -p 5432:5432 \
  -d postgres:15

# OR MySQL
docker run --name scriber-db \
  -e MYSQL_ROOT_PASSWORD=yourpassword \
  -e MYSQL_DATABASE=scriber \
  -p 3306:3306 \
  -d mysql:8
```

### 9.2 Start Object Storage (Docker)

```bash
# MinIO (S3-compatible)
docker run --name scriber-storage \
  -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=admin \
  -e MINIO_ROOT_PASSWORD=yourpassword \
  -d minio/minio server /data --console-address ":9001"
```

### 9.3 Run Migrations

Run your ORM's migration command (see Step 6)

### 9.4 Run the API

Start your application using your language/framework's command

Open browser: `http://localhost:PORT/docs` or `/swagger`

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

## Production Deployment

### Prerequisites

- Cloud provider account or on-premises infrastructure
- CLI tools for your deployment platform
- Infrastructure as Code templates (Terraform, Pulumi, etc.)

### Resources to Create

1. **Container Platform** - API hosting (Kubernetes, ECS, Cloud Run, etc.)
2. **Managed Database** - PostgreSQL/MySQL database service
3. **Object Storage** - S3-compatible or cloud storage for media files
4. **CDN** - Content delivery network for media
5. **Monitoring** - Observability platform (Prometheus/Grafana, DataDog, etc.)
6. **Secrets Management** - Vault or secrets manager service

### Deployment Steps

```bash
# Build Docker image
docker build -t scriber-api:latest .

# Tag and push to registry
docker tag scriber-api:latest your-registry.com/scriber-api:latest
docker push your-registry.com/scriber-api:latest

# Deploy using your platform
# Kubernetes:
kubectl apply -f k8s/deployment.yaml

# Cloud-specific CLI:
# AWS: aws ecs update-service ...
# GCP: gcloud run deploy ...
# Azure: az containerapp update ...
```

---

## Troubleshooting

### Common Issues

**Issue:** "Mediator/Handler not registered"
- **Solution:** Ensure mediator and all handlers are registered in your DI container

**Issue:** Database migrations fail
- **Solution:** Check connection string, ensure database server is running and accessible

**Issue:** JWT authentication fails
- **Solution:** Verify JWT secret key matches in configuration file

**Issue:** Stripe webhook signature invalid
- **Solution:** Use correct webhook secret from Stripe dashboard

---

## Next Steps

1. Implement remaining bounded contexts (Media, Notifications)
2. Add background job processing for scheduled posts (workers, cron jobs, serverless functions)
3. Implement analytics tracking
4. Add caching layer (Redis, Memcached, or in-memory cache)
5. Set up CI/CD pipeline (GitHub Actions, GitLab CI, Jenkins, etc.)
6. Configure monitoring, logging, and alerting

---

## Resources

- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [Domain-Driven Design](https://martinfowler.com/bliki/DomainDrivenDesign.html)
- [CQRS Pattern](https://martinfowler.com/bliki/CQRS.html)
- [Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html)
- [API Design Best Practices](https://swagger.io/resources/articles/best-practices-in-api-design/)
- Payment Provider Documentation (Stripe, PayPal, etc.)
- Email Service Documentation (SendGrid, Mailgun, SES, etc.)

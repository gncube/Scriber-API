# SPEC-5: Infrastructure Layer - Persistence & External Services

## Overview

This document defines the Infrastructure Layer for Scriber API, implementing persistence using EF Core, repositories, and external service integrations. This layer provides concrete implementations of abstractions defined in the Application and Domain layers.

**Principles:**
- Repository pattern per aggregate root
- Unit of Work for transaction management
- EF Core for ORM with explicit configurations
- Separate schemas per bounded context
- Domain events dispatched after SaveChanges

---

## Layer Structure

```
Scriber.Infrastructure/
├── Persistence/
│   ├── Configurations/          # EF Core entity configurations
│   │   ├── Publishing/
│   │   │   ├── PostConfiguration.cs
│   │   │   ├── PublicationConfiguration.cs
│   │   │   └── TagConfiguration.cs
│   │   ├── Subscriptions/
│   │   └── Payments/
│   ├── Contexts/
│   │   ├── PublishingDbContext.cs
│   │   ├── SubscriptionDbContext.cs
│   │   └── PaymentDbContext.cs
│   ├── Repositories/
│   │   ├── PostRepository.cs
│   │   ├── SubscriptionRepository.cs
│   │   └── PaymentRepository.cs
│   ├── Migrations/
│   └── UnitOfWork.cs
├── Services/
│   ├── EmailService.cs
│   ├── PaymentService.cs (Stripe integration)
│   └── BlobStorageService.cs
├── Identity/
│   └── CurrentUserService.cs
└── Extensions/
    └── DependencyInjection.cs
```

---

## Base DbContext with Domain Event Dispatch

```csharp
namespace Scriber.Infrastructure.Persistence;

using Microsoft.EntityFrameworkCore;
using Scriber.Application.Common.Messaging;
using Scriber.Domain.SeedWork;

public abstract class BaseDbContext : DbContext
{
    private readonly IMediator _mediator;

    protected BaseDbContext(DbContextOptions options, IMediator mediator) : base(options)
    {
        _mediator = mediator;
    }

    public override async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        // Collect domain events before saving
        var aggregatesWithEvents = ChangeTracker
            .Entries<AggregateRoot<object>>()
            .Where(e => e.Entity.DomainEvents.Any())
            .Select(e => e.Entity)
            .ToList();

        var domainEvents = aggregatesWithEvents
            .SelectMany(a => a.DomainEvents)
            .ToList();

        // Save changes to database first
        var result = await base.SaveChangesAsync(cancellationToken);

        // Dispatch domain events after successful save
        if (domainEvents.Any())
        {
            foreach (var domainEvent in domainEvents)
            {
                await _mediator.Publish(domainEvent, cancellationToken);
            }

            // Clear events after dispatching
            foreach (var aggregate in aggregatesWithEvents)
            {
                aggregate.ClearDomainEvents();
            }
        }

        return result;
    }
}
```

---

## Publishing Context

### 1. PublishingDbContext

```csharp
namespace Scriber.Infrastructure.Persistence.Contexts;

using Microsoft.EntityFrameworkCore;
using Scriber.Application.Common.Interfaces;
using Scriber.Application.Common.Messaging;
using Scriber.Domain.Publishing;

public class PublishingDbContext : BaseDbContext, IPublishingDbContext
{
    public DbSet<Post> Posts => Set<Post>();
    public DbSet<Publication> Publications => Set<Publication>();
    public DbSet<Tag> Tags => Set<Tag>();

    public PublishingDbContext(
        DbContextOptions<PublishingDbContext> options,
        IMediator mediator) : base(options, mediator)
    {
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("Publishing");

        // Apply all configurations from this assembly
        modelBuilder.ApplyConfigurationsFromAssembly(
            typeof(PublishingDbContext).Assembly,
            t => t.Namespace?.Contains("Publishing") == true);

        base.OnModelCreating(modelBuilder);
    }
}

// Interface for Application layer
public interface IPublishingDbContext
{
    DbSet<Post> Posts { get; }
    DbSet<Publication> Publications { get; }
    DbSet<Tag> Tags { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
```

### 2. EF Core Entity Configurations

#### Post Configuration

```csharp
namespace Scriber.Infrastructure.Persistence.Configurations.Publishing;

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Scriber.Domain.Publishing;

public class PostConfiguration : IEntityTypeConfiguration<Post>
{
    public void Configure(EntityTypeBuilder<Post> builder)
    {
        builder.ToTable("Posts", "Publishing");

        // Primary key
        builder.HasKey(p => p.Id);
        builder.Property(p => p.Id)
            .HasConversion(
                id => id.Value,
                value => new PostId(value))
            .ValueGeneratedNever();

        // Foreign keys (value objects)
        builder.Property(p => p.PublicationId)
            .HasConversion(
                id => id.Value,
                value => new PublicationId(value))
            .IsRequired();

        builder.Property(p => p.AuthorId)
            .HasConversion(
                id => id.Value,
                value => new AuthorId(value))
            .IsRequired();

        // Value Objects - Owned Types
        builder.OwnsOne(p => p.Title, title =>
        {
            title.Property(t => t.Value)
                .HasColumnName("Title")
                .HasMaxLength(300)
                .IsRequired();
        });

        builder.OwnsOne(p => p.Slug, slug =>
        {
            slug.Property(s => s.Value)
                .HasColumnName("Slug")
                .HasMaxLength(300)
                .IsRequired();
            slug.HasIndex(s => s.Value);
        });

        builder.OwnsOne(p => p.Content, content =>
        {
            content.Property(c => c.Value)
                .HasColumnName("Content")
                .HasColumnType("jsonb") // PostgreSQL JSONB for structured content
                .IsRequired();
        });

        builder.OwnsOne(p => p.Excerpt, excerpt =>
        {
            excerpt.Property(e => e.Value)
                .HasColumnName("Excerpt")
                .HasMaxLength(500);
        });

        // Enums
        builder.Property(p => p.Status)
            .HasConversion<string>()
            .HasMaxLength(20)
            .IsRequired();

        builder.Property(p => p.Visibility)
            .HasConversion<string>()
            .HasMaxLength(30)
            .IsRequired();

        // Timestamps
        builder.Property(p => p.PublishedAt)
            .IsRequired(false);

        builder.Property(p => p.ScheduledFor)
            .IsRequired(false);

        builder.Property(p => p.CreatedAt)
            .IsRequired()
            .HasDefaultValueSql("NOW()");

        builder.Property(p => p.UpdatedAt)
            .IsRequired()
            .HasDefaultValueSql("NOW()");

        // Relationships
        builder.HasOne<Publication>()
            .WithMany()
            .HasForeignKey(p => p.PublicationId)
            .OnDelete(DeleteBehavior.Cascade);

        // Many-to-many with Tags
        builder.HasMany(p => p.Tags)
            .WithMany()
            .UsingEntity<Dictionary<string, object>>(
                "PostTags",
                j => j.HasOne<Tag>().WithMany().HasForeignKey("TagId"),
                j => j.HasOne<Post>().WithMany().HasForeignKey("PostId"),
                j =>
                {
                    j.ToTable("PostTags", "Publishing");
                    j.HasKey("PostId", "TagId");
                });

        // Indexes
        builder.HasIndex(p => new { p.PublicationId, p.Slug })
            .IsUnique()
            .HasFilter("\"Status\" = 'Published'"); // Partial index for published posts

        builder.HasIndex(p => p.Status);
        builder.HasIndex(p => p.PublishedAt);

        // Full-text search index (PostgreSQL specific)
        builder.HasIndex(p => new { p.Title, p.Content })
            .HasMethod("GIN")
            .HasAnnotation("Npgsql:TsVectorConfig", "english");

        // Ignore domain events (not persisted)
        builder.Ignore(p => p.DomainEvents);
    }
}
```

#### Publication Configuration

```csharp
namespace Scriber.Infrastructure.Persistence.Configurations.Publishing;

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Scriber.Domain.Publishing;

public class PublicationConfiguration : IEntityTypeConfiguration<Publication>
{
    public void Configure(EntityTypeBuilder<Publication> builder)
    {
        builder.ToTable("Publications", "Publishing");

        builder.HasKey(p => p.Id);
        builder.Property(p => p.Id)
            .HasConversion(
                id => id.Value,
                value => new PublicationId(value))
            .ValueGeneratedNever();

        builder.Property(p => p.Name)
            .HasMaxLength(200)
            .IsRequired();

        builder.OwnsOne(p => p.Slug, slug =>
        {
            slug.Property(s => s.Value)
                .HasColumnName("Slug")
                .HasMaxLength(100)
                .IsRequired();
            slug.HasIndex(s => s.Value).IsUnique();
        });

        builder.Property(p => p.OwnerId)
            .HasConversion(
                id => id.Value,
                value => new AuthorId(value))
            .IsRequired();

        // Settings as JSONB
        builder.Property(p => p.Settings)
            .HasColumnType("jsonb")
            .HasDefaultValue("{}");

        builder.Property(p => p.CreatedAt)
            .IsRequired()
            .HasDefaultValueSql("NOW()");

        builder.Ignore(p => p.DomainEvents);
    }
}
```

#### Tag Configuration

```csharp
namespace Scriber.Infrastructure.Persistence.Configurations.Publishing;

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Scriber.Domain.Publishing;

public class TagConfiguration : IEntityTypeConfiguration<Tag>
{
    public void Configure(EntityTypeBuilder<Tag> builder)
    {
        builder.ToTable("Tags", "Publishing");

        builder.HasKey(t => t.Id);
        builder.Property(t => t.Id)
            .HasConversion(
                id => id.Value,
                value => new TagId(value))
            .ValueGeneratedNever();

        builder.Property(t => t.PublicationId)
            .HasConversion(
                id => id.Value,
                value => new PublicationId(value))
            .IsRequired();

        builder.Property(t => t.Name)
            .HasMaxLength(50)
            .IsRequired();

        builder.OwnsOne(t => t.Slug, slug =>
        {
            slug.Property(s => s.Value)
                .HasColumnName("Slug")
                .HasMaxLength(50)
                .IsRequired();
        });

        // Unique constraint on publication + slug
        builder.HasIndex(t => new { t.PublicationId, t.Slug })
            .IsUnique();
    }
}
```

### 3. Post Repository

```csharp
namespace Scriber.Infrastructure.Persistence.Repositories;

using Microsoft.EntityFrameworkCore;
using Scriber.Application.Common.Interfaces;
using Scriber.Domain.Publishing;

public class PostRepository : IPostRepository
{
    private readonly PublishingDbContext _context;

    public PostRepository(PublishingDbContext context)
    {
        _context = context;
    }

    public async Task<Post?> GetByIdAsync(PostId id, CancellationToken cancellationToken = default)
    {
        return await _context.Posts
            .Include(p => p.Tags)
            .FirstOrDefaultAsync(p => p.Id == id, cancellationToken);
    }

    public async Task<Post?> GetBySlugAsync(
        PublicationId publicationId,
        Slug slug,
        CancellationToken cancellationToken = default)
    {
        return await _context.Posts
            .Include(p => p.Tags)
            .FirstOrDefaultAsync(
                p => p.PublicationId == publicationId && p.Slug == slug,
                cancellationToken);
    }

    public async Task<List<Post>> GetScheduledPostsAsync(CancellationToken cancellationToken = default)
    {
        return await _context.Posts
            .Where(p => p.Status == PostStatus.Scheduled && p.ScheduledFor <= DateTime.UtcNow)
            .ToListAsync(cancellationToken);
    }

    public async Task AddAsync(Post post, CancellationToken cancellationToken = default)
    {
        await _context.Posts.AddAsync(post, cancellationToken);
    }

    public Task UpdateAsync(Post post, CancellationToken cancellationToken = default)
    {
        _context.Posts.Update(post);
        return Task.CompletedTask;
    }

    public Task DeleteAsync(PostId id, CancellationToken cancellationToken = default)
    {
        var post = _context.Posts.Find(id);
        if (post != null)
        {
            _context.Posts.Remove(post);
        }
        return Task.CompletedTask;
    }
}

// Interface (in Application layer)
public interface IPostRepository
{
    Task<Post?> GetByIdAsync(PostId id, CancellationToken cancellationToken = default);
    Task<Post?> GetBySlugAsync(PublicationId publicationId, Slug slug, CancellationToken cancellationToken = default);
    Task<List<Post>> GetScheduledPostsAsync(CancellationToken cancellationToken = default);
    Task AddAsync(Post post, CancellationToken cancellationToken = default);
    Task UpdateAsync(Post post, CancellationToken cancellationToken = default);
    Task DeleteAsync(PostId id, CancellationToken cancellationToken = default);
}
```

---

## Subscription Context

### 1. SubscriptionDbContext

```csharp
namespace Scriber.Infrastructure.Persistence.Contexts;

using Microsoft.EntityFrameworkCore;
using Scriber.Application.Common.Messaging;
using Scriber.Domain.Subscriptions;

public class SubscriptionDbContext : BaseDbContext
{
    public DbSet<Subscription> Subscriptions => Set<Subscription>();
    public DbSet<Subscriber> Subscribers => Set<Subscriber>();
    public DbSet<SubscriptionTier> SubscriptionTiers => Set<SubscriptionTier>();

    public SubscriptionDbContext(
        DbContextOptions<SubscriptionDbContext> options,
        IMediator mediator) : base(options, mediator)
    {
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("Subscription");

        modelBuilder.ApplyConfigurationsFromAssembly(
            typeof(SubscriptionDbContext).Assembly,
            t => t.Namespace?.Contains("Subscriptions") == true);

        base.OnModelCreating(modelBuilder);
    }
}
```

### 2. Subscription Configuration

```csharp
namespace Scriber.Infrastructure.Persistence.Configurations.Subscriptions;

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Scriber.Domain.Subscriptions;

public class SubscriptionConfiguration : IEntityTypeConfiguration<Subscription>
{
    public void Configure(EntityTypeBuilder<Subscription> builder)
    {
        builder.ToTable("Subscriptions", "Subscription");

        builder.HasKey(s => s.Id);
        builder.Property(s => s.Id)
            .HasConversion(
                id => id.Value,
                value => new SubscriptionId(value))
            .ValueGeneratedNever();

        // Foreign keys
        builder.Property(s => s.SubscriberId)
            .HasConversion(
                id => id.Value,
                value => new SubscriberId(value))
            .IsRequired();

        builder.Property(s => s.PublicationId)
            .HasConversion(
                id => id.Value,
                value => new PublicationId(value))
            .IsRequired();

        builder.Property(s => s.TierId)
            .HasConversion(
                id => id.Value,
                value => new TierId(value))
            .IsRequired();

        // Enums
        builder.Property(s => s.Status)
            .HasConversion<string>()
            .HasMaxLength(20)
            .IsRequired();

        builder.Property(s => s.BillingCycle)
            .HasConversion<string>()
            .HasMaxLength(20)
            .IsRequired();

        // Value Objects - Trial Period
        builder.OwnsOne(s => s.TrialPeriod, trial =>
        {
            trial.Property(t => t.DurationDays)
                .HasColumnName("TrialDurationDays");
            trial.Property(t => t.StartDate)
                .HasColumnName("TrialStartDate");
            trial.Property(t => t.EndDate)
                .HasColumnName("TrialEndDate");
        });

        builder.Property(s => s.CurrentPeriodEnd)
            .IsRequired(false);

        builder.Property(s => s.ExternalSubscriptionId)
            .HasMaxLength(255)
            .IsRequired(false);

        builder.Property(s => s.CreatedAt)
            .IsRequired()
            .HasDefaultValueSql("NOW()");

        builder.Property(s => s.UpdatedAt)
            .IsRequired()
            .HasDefaultValueSql("NOW()");

        // Relationships
        builder.HasOne<Subscriber>()
            .WithMany()
            .HasForeignKey(s => s.SubscriberId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne<SubscriptionTier>()
            .WithMany()
            .HasForeignKey(s => s.TierId)
            .OnDelete(DeleteBehavior.Restrict);

        // Indexes
        builder.HasIndex(s => s.SubscriberId);
        builder.HasIndex(s => s.Status);
        builder.HasIndex(s => s.ExternalSubscriptionId).IsUnique();

        builder.Ignore(s => s.DomainEvents);
    }
}
```

### 3. Subscription Tier Configuration

```csharp
namespace Scriber.Infrastructure.Persistence.Configurations.Subscriptions;

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Scriber.Domain.Subscriptions;

public class SubscriptionTierConfiguration : IEntityTypeConfiguration<SubscriptionTier>
{
    public void Configure(EntityTypeBuilder<SubscriptionTier> builder)
    {
        builder.ToTable("SubscriptionTiers", "Subscription");

        builder.HasKey(t => t.Id);
        builder.Property(t => t.Id)
            .HasConversion(
                id => id.Value,
                value => new TierId(value))
            .ValueGeneratedNever();

        builder.Property(t => t.PublicationId)
            .HasConversion(
                id => id.Value,
                value => new PublicationId(value))
            .IsRequired();

        builder.Property(t => t.Name)
            .HasMaxLength(100)
            .IsRequired();

        // Money Value Object
        builder.OwnsOne(t => t.Price, price =>
        {
            price.Property(p => p.AmountInCents)
                .HasColumnName("PriceCents")
                .IsRequired();
            price.Property(p => p.Currency)
                .HasColumnName("Currency")
                .HasMaxLength(3)
                .IsRequired();
        });

        builder.Property(t => t.BillingCycle)
            .HasConversion<string>()
            .HasMaxLength(20)
            .IsRequired();

        builder.Property(t => t.TrialDays)
            .HasDefaultValue(0);

        builder.Property(t => t.StripePriceId)
            .HasMaxLength(255)
            .IsRequired(false);

        builder.HasIndex(t => new { t.PublicationId, t.Name })
            .IsUnique();
    }
}
```

### 4. Subscription Repository

```csharp
namespace Scriber.Infrastructure.Persistence.Repositories;

using Microsoft.EntityFrameworkCore;
using Scriber.Application.Common.Interfaces;
using Scriber.Domain.Subscriptions;

public class SubscriptionRepository : ISubscriptionRepository
{
    private readonly SubscriptionDbContext _context;

    public SubscriptionRepository(SubscriptionDbContext context)
    {
        _context = context;
    }

    public async Task<Subscription?> GetByIdAsync(
        SubscriptionId id,
        CancellationToken cancellationToken = default)
    {
        return await _context.Subscriptions
            .FirstOrDefaultAsync(s => s.Id == id, cancellationToken);
    }

    public async Task<Subscription?> GetActiveSubscriptionAsync(
        SubscriberId subscriberId,
        CancellationToken cancellationToken = default)
    {
        return await _context.Subscriptions
            .Where(s => s.SubscriberId == subscriberId)
            .Where(s => s.Status == SubscriptionStatus.Active || s.Status == SubscriptionStatus.Trialing)
            .FirstOrDefaultAsync(cancellationToken);
    }

    public async Task<Subscription?> GetByExternalIdAsync(
        string externalSubscriptionId,
        CancellationToken cancellationToken = default)
    {
        return await _context.Subscriptions
            .FirstOrDefaultAsync(
                s => s.ExternalSubscriptionId == externalSubscriptionId,
                cancellationToken);
    }

    public async Task<List<Subscription>> GetExpiringSubscriptionsAsync(
        DateTime expirationDate,
        CancellationToken cancellationToken = default)
    {
        return await _context.Subscriptions
            .Where(s => s.Status == SubscriptionStatus.Active)
            .Where(s => s.CurrentPeriodEnd <= expirationDate)
            .ToListAsync(cancellationToken);
    }

    public async Task AddAsync(Subscription subscription, CancellationToken cancellationToken = default)
    {
        await _context.Subscriptions.AddAsync(subscription, cancellationToken);
    }

    public Task UpdateAsync(Subscription subscription, CancellationToken cancellationToken = default)
    {
        _context.Subscriptions.Update(subscription);
        return Task.CompletedTask;
    }
}
```

---

## Unit of Work Pattern

```csharp
namespace Scriber.Infrastructure.Persistence;

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Scriber.Application.Common.Interfaces;

public class UnitOfWork : IUnitOfWork
{
    private readonly PublishingDbContext _publishingContext;
    private readonly SubscriptionDbContext _subscriptionContext;
    private readonly PaymentDbContext _paymentContext;

    public UnitOfWork(
        PublishingDbContext publishingContext,
        SubscriptionDbContext subscriptionContext,
        PaymentDbContext paymentContext)
    {
        _publishingContext = publishingContext;
        _subscriptionContext = subscriptionContext;
        _paymentContext = paymentContext;
    }

    public async Task<IDbContextTransaction> BeginTransactionAsync(
        CancellationToken cancellationToken = default)
    {
        // For single database with multiple schemas, use one transaction
        return await _publishingContext.Database.BeginTransactionAsync(cancellationToken);
    }

    public async Task CommitTransactionAsync(
        IDbContextTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await _publishingContext.SaveChangesAsync(cancellationToken);
            await _subscriptionContext.SaveChangesAsync(cancellationToken);
            await _paymentContext.SaveChangesAsync(cancellationToken);
            
            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }
    }

    public async Task RollbackTransactionAsync(
        IDbContextTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        await transaction.RollbackAsync(cancellationToken);
    }
}

// Interface (in Application layer)
public interface IUnitOfWork
{
    Task<IDbContextTransaction> BeginTransactionAsync(CancellationToken cancellationToken = default);
    Task CommitTransactionAsync(IDbContextTransaction transaction, CancellationToken cancellationToken = default);
    Task RollbackTransactionAsync(IDbContextTransaction transaction, CancellationToken cancellationToken = default);
}
```

---

## External Services

### 1. Email Service (SendGrid)

```csharp
namespace Scriber.Infrastructure.Services;

using SendGrid;
using SendGrid.Helpers.Mail;
using Scriber.Application.Common.Interfaces;
using Microsoft.Extensions.Options;

public class EmailService : IEmailService
{
    private readonly SendGridClient _client;
    private readonly EmailSettings _settings;
    private readonly ILogger<EmailService> _logger;

    public EmailService(
        IOptions<EmailSettings> settings,
        ILogger<EmailService> logger)
    {
        _settings = settings.Value;
        _client = new SendGridClient(_settings.ApiKey);
        _logger = logger;
    }

    public async Task QueueNewPostEmailAsync(
        PublicationId publicationId,
        PostId postId,
        string postTitle,
        List<string> recipientEmails,
        CancellationToken cancellationToken)
    {
        // For MVP, send emails directly (later: use Azure Service Bus queue)
        var from = new EmailAddress(_settings.FromEmail, _settings.FromName);
        var subject = $"New post: {postTitle}";
        
        var messages = recipientEmails.Select(email => MailHelper.CreateSingleEmail(
            from,
            new EmailAddress(email),
            subject,
            plainTextContent: $"Read the new post: {postTitle}",
            htmlContent: $"<p>Read the new post: <a href='#'>{postTitle}</a></p>"));

        foreach (var message in messages)
        {
            try
            {
                var response = await _client.SendEmailAsync(message, cancellationToken);
                _logger.LogInformation("Email sent to {Email}, Status: {StatusCode}", 
                    message.Personalizations[0].Tos[0].Email, response.StatusCode);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to send email to {Email}", 
                    message.Personalizations[0].Tos[0].Email);
            }
        }
    }

    public async Task SendWelcomeEmailAsync(string email, CancellationToken cancellationToken)
    {
        var from = new EmailAddress(_settings.FromEmail, _settings.FromName);
        var to = new EmailAddress(email);
        var message = MailHelper.CreateSingleEmail(
            from,
            to,
            "Welcome to our publication!",
            "Thank you for subscribing.",
            "<p>Thank you for subscribing!</p>");

        await _client.SendEmailAsync(message, cancellationToken);
    }
}

public class EmailSettings
{
    public string ApiKey { get; set; } = string.Empty;
    public string FromEmail { get; set; } = string.Empty;
    public string FromName { get; set; } = string.Empty;
}
```

### 2. Payment Service (Stripe)

```csharp
namespace Scriber.Infrastructure.Services;

using Stripe;
using Scriber.Application.Common.Interfaces;
using Microsoft.Extensions.Options;

public class PaymentService : IPaymentService
{
    private readonly StripeSettings _settings;
    private readonly ILogger<PaymentService> _logger;

    public PaymentService(
        IOptions<StripeSettings> settings,
        ILogger<PaymentService> logger)
    {
        _settings = settings.Value;
        StripeConfiguration.ApiKey = _settings.SecretKey;
        _logger = logger;
    }

    public async Task<PaymentResult> CreateSubscriptionAsync(
        SubscriptionId subscriptionId,
        string stripePriceId,
        string paymentMethodToken,
        CancellationToken cancellationToken)
    {
        try
        {
            // Create or retrieve customer
            var customerService = new CustomerService();
            var customer = await customerService.CreateAsync(new CustomerCreateOptions
            {
                PaymentMethod = paymentMethodToken,
                InvoiceSettings = new CustomerInvoiceSettingsOptions
                {
                    DefaultPaymentMethod = paymentMethodToken
                },
                Metadata = new Dictionary<string, string>
                {
                    ["SubscriptionId"] = subscriptionId.Value.ToString()
                }
            }, cancellationToken: cancellationToken);

            // Create subscription
            var subscriptionService = new Stripe.SubscriptionService();
            var subscription = await subscriptionService.CreateAsync(new SubscriptionCreateOptions
            {
                Customer = customer.Id,
                Items = new List<SubscriptionItemOptions>
                {
                    new() { Price = stripePriceId }
                },
                PaymentBehavior = "default_incomplete",
                Metadata = new Dictionary<string, string>
                {
                    ["SubscriptionId"] = subscriptionId.Value.ToString()
                }
            }, cancellationToken: cancellationToken);

            return new PaymentResult
            {
                Succeeded = subscription.Status == "active" || subscription.Status == "trialing",
                ExternalSubscriptionId = subscription.Id
            };
        }
        catch (StripeException ex)
        {
            _logger.LogError(ex, "Stripe error creating subscription");
            return new PaymentResult
            {
                Succeeded = false,
                ErrorMessage = ex.Message
            };
        }
    }

    public async Task CancelSubscriptionAsync(
        string externalSubscriptionId,
        CancellationToken cancellationToken)
    {
        var service = new Stripe.SubscriptionService();
        await service.CancelAsync(externalSubscriptionId, cancellationToken: cancellationToken);
    }
}

public class StripeSettings
{
    public string SecretKey { get; set; } = string.Empty;
    public string WebhookSecret { get; set; } = string.Empty;
}
```

### 3. Blob Storage Service (Azure)

```csharp
namespace Scriber.Infrastructure.Services;

using Azure.Storage.Blobs;
using Azure.Storage.Sas;
using Scriber.Application.Common.Interfaces;
using Microsoft.Extensions.Options;

public class BlobStorageService : IBlobStorageService
{
    private readonly BlobServiceClient _blobServiceClient;
    private readonly BlobStorageSettings _settings;

    public BlobStorageService(IOptions<BlobStorageSettings> settings)
    {
        _settings = settings.Value;
        _blobServiceClient = new BlobServiceClient(_settings.ConnectionString);
    }

    public async Task<string> GetUploadSasTokenAsync(
        string containerName,
        string blobName,
        TimeSpan expiresIn,
        CancellationToken cancellationToken = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(containerName);
        await containerClient.CreateIfNotExistsAsync(cancellationToken: cancellationToken);

        var blobClient = containerClient.GetBlobClient(blobName);

        var sasBuilder = new BlobSasBuilder
        {
            BlobContainerName = containerName,
            BlobName = blobName,
            Resource = "b",
            ExpiresOn = DateTimeOffset.UtcNow.Add(expiresIn)
        };
        sasBuilder.SetPermissions(BlobSasPermissions.Write | BlobSasPermissions.Create);

        var sasToken = blobClient.GenerateSasUri(sasBuilder).ToString();
        return sasToken;
    }

    public string GetBlobUrl(string containerName, string blobName)
    {
        return $"{_settings.BlobEndpoint}/{containerName}/{blobName}";
    }
}

public class BlobStorageSettings
{
    public string ConnectionString { get; set; } = string.Empty;
    public string BlobEndpoint { get; set; } = string.Empty;
}

public interface IBlobStorageService
{
    Task<string> GetUploadSasTokenAsync(
        string containerName,
        string blobName,
        TimeSpan expiresIn,
        CancellationToken cancellationToken = default);
    
    string GetBlobUrl(string containerName, string blobName);
}
```

---

## Identity & Current User Service

```csharp
namespace Scriber.Infrastructure.Identity;

using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Scriber.Application.Common.Interfaces;

public class CurrentUserService : ICurrentUserService
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public CurrentUserService(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public Guid? UserId
    {
        get
        {
            var userIdClaim = _httpContextAccessor.HttpContext?.User
                ?.FindFirst(ClaimTypes.NameIdentifier)?.Value;

            return Guid.TryParse(userIdClaim, out var userId) ? userId : null;
        }
    }

    public string? Email =>
        _httpContextAccessor.HttpContext?.User?.FindFirst(ClaimTypes.Email)?.Value;

    public async Task<bool> HasRoleAsync(string role)
    {
        var user = _httpContextAccessor.HttpContext?.User;
        return user?.IsInRole(role) ?? false;
    }

    public async Task<bool> IsInPublicationAsync(Guid publicationId)
    {
        // TODO: Implement publication membership check
        // Query database to see if user is owner/editor of publication
        return true;
    }
}
```

---

## Dependency Injection

```csharp
namespace Scriber.Infrastructure;

using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Scriber.Application.Common.Interfaces;
using Scriber.Infrastructure.Persistence;
using Scriber.Infrastructure.Persistence.Repositories;
using Scriber.Infrastructure.Services;
using Scriber.Infrastructure.Identity;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // Database contexts
        var connectionString = configuration.GetConnectionString("DefaultConnection");

        services.AddDbContext<PublishingDbContext>(options =>
            options.UseNpgsql(connectionString)
                .UseSnakeCaseNamingConvention());

        services.AddDbContext<SubscriptionDbContext>(options =>
            options.UseNpgsql(connectionString)
                .UseSnakeCaseNamingConvention());

        services.AddDbContext<PaymentDbContext>(options =>
            options.UseNpgsql(connectionString)
                .UseSnakeCaseNamingConvention());

        // Repositories
        services.AddScoped<IPostRepository, PostRepository>();
        services.AddScoped<ISubscriptionRepository, SubscriptionRepository>();
        services.AddScoped<ISubscriberRepository, SubscriberRepository>();
        services.AddScoped<IPaymentRepository, PaymentRepository>();

        // Unit of Work
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        // Services
        services.AddScoped<ICurrentUserService, CurrentUserService>();
        services.AddScoped<IEmailService, EmailService>();
        services.AddScoped<IPaymentService, PaymentService>();
        services.AddScoped<IBlobStorageService, BlobStorageService>();

        // Settings
        services.Configure<EmailSettings>(configuration.GetSection("Email"));
        services.Configure<StripeSettings>(configuration.GetSection("Stripe"));
        services.Configure<BlobStorageSettings>(configuration.GetSection("BlobStorage"));

        // HTTP Context Accessor
        services.AddHttpContextAccessor();

        return services;
    }
}
```

---

## appsettings.json Configuration

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=scriber;Username=postgres;Password=yourpassword"
  },
  "Email": {
    "ApiKey": "SG.your-sendgrid-api-key",
    "FromEmail": "noreply@yourdomain.com",
    "FromName": "Scriber"
  },
  "Stripe": {
    "SecretKey": "sk_test_your-stripe-secret-key",
    "WebhookSecret": "whsec_your-webhook-secret"
  },
  "BlobStorage": {
    "ConnectionString": "DefaultEndpointsProtocol=https;AccountName=youraccountname;AccountKey=yourkey",
    "BlobEndpoint": "https://youraccountname.blob.core.windows.net"
  }
}
```

---

## Summary

This infrastructure layer provides:

✅ **EF Core with explicit configurations** - Type-safe, maintainable  
✅ **Separate schemas per bounded context** - Logical separation in single database  
✅ **Repository pattern** - Clean abstraction over data access  
✅ **Unit of Work** - Transaction management across contexts  
✅ **Domain event dispatch** - Integrated with SaveChanges  
✅ **External service integrations** - Email, payments, blob storage  
✅ **Value object conversions** - Proper domain modeling  
✅ **Frugal approach** - Single database, schema separation (not microservices yet)  

**Next:** SPEC-6 (API Contracts - REST endpoints, DTOs, OpenAPI)

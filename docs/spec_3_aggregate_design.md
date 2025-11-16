# SPEC-3: Aggregate Design & Domain Models

## Overview

This document provides detailed aggregate designs for each bounded context, following DDD tactical patterns with .NET implementation in mind.

---

## Publishing Context

### Post Aggregate

**Aggregate Root:** `Post`

#### Entities & Value Objects

```csharp
// Aggregate Root
public class Post : AggregateRoot<PostId>
{
    private readonly List<PostTag> _tags = new();
    private readonly List<PostRevision> _revisions = new();

    public PublicationId PublicationId { get; private set; }
    public AuthorId AuthorId { get; private set; }
    public PostTitle Title { get; private set; }
    public Slug Slug { get; private set; }
    public PostStatus Status { get; private set; }
    public PostContent Content { get; private set; }
    public Excerpt Excerpt { get; private set; }
    public VisibilityTier Visibility { get; private set; }
    public DateTime? PublishedAt { get; private set; }
    public DateTime? ScheduledFor { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public DateTime UpdatedAt { get; private set; }

    public IReadOnlyCollection<PostTag> Tags => _tags.AsReadOnly();
    public IReadOnlyCollection<PostRevision> Revisions => _revisions.AsReadOnly();

    // Factory method
    public static Post CreateDraft(
        PublicationId publicationId,
        AuthorId authorId,
        PostTitle title,
        PostContent content,
        VisibilityTier visibility)
    {
        var post = new Post
        {
            Id = PostId.NewId(),
            PublicationId = publicationId,
            AuthorId = authorId,
            Title = title,
            Slug = Slug.FromTitle(title.Value),
            Status = PostStatus.Draft,
            Content = content,
            Excerpt = Excerpt.FromContent(content.Value),
            Visibility = visibility,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        post.AddDomainEvent(new PostDraftedEvent(post.Id, post.PublicationId, post.AuthorId));
        return post;
    }

    // Commands (behaviors)
    public void UpdateContent(PostTitle title, PostContent content, VisibilityTier visibility)
    {
        if (Status == PostStatus.Published)
            throw new DomainException("Cannot modify published post directly. Create a revision or unpublish first.");

        Title = title;
        Content = content;
        Excerpt = Excerpt.FromContent(content.Value);
        Visibility = visibility;
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new PostUpdatedEvent(Id, PublicationId));
    }

    public void Publish()
    {
        if (Status == PostStatus.Published)
            throw new DomainException("Post is already published.");

        if (ScheduledFor.HasValue && ScheduledFor > DateTime.UtcNow)
            throw new DomainException("Cannot publish a scheduled post before its scheduled time.");

        Status = PostStatus.Published;
        PublishedAt = DateTime.UtcNow;
        ScheduledFor = null;
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new PostPublishedEvent(Id, PublicationId, Title.Value, Visibility));
    }

    public void Schedule(DateTime scheduledFor)
    {
        if (scheduledFor <= DateTime.UtcNow)
            throw new DomainException("Scheduled time must be in the future.");

        Status = PostStatus.Scheduled;
        ScheduledFor = scheduledFor;
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new PostScheduledEvent(Id, PublicationId, scheduledFor));
    }

    public void Unpublish()
    {
        if (Status != PostStatus.Published)
            throw new DomainException("Only published posts can be unpublished.");

        Status = PostStatus.Draft;
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new PostUnpublishedEvent(Id, PublicationId));
    }

    public void AddTag(TagId tagId, string tagName)
    {
        if (_tags.Any(t => t.TagId == tagId))
            return; // Idempotent

        _tags.Add(new PostTag(Id, tagId, tagName));
        UpdatedAt = DateTime.UtcNow;
    }

    public void RemoveTag(TagId tagId)
    {
        var tag = _tags.FirstOrDefault(t => t.TagId == tagId);
        if (tag != null)
        {
            _tags.Remove(tag);
            UpdatedAt = DateTime.UtcNow;
        }
    }

    // Invariants check
    protected override void Validate()
    {
        if (PublicationId == null) throw new DomainException("Post must belong to a publication.");
        if (AuthorId == null) throw new DomainException("Post must have an author.");
        if (Title == null || string.IsNullOrWhiteSpace(Title.Value))
            throw new DomainException("Post title is required.");
    }
}

// Entity
public class PostTag
{
    public PostId PostId { get; private set; }
    public TagId TagId { get; private set; }
    public string TagName { get; private set; } // Denormalized for read performance

    public PostTag(PostId postId, TagId tagId, string tagName)
    {
        PostId = postId;
        TagId = tagId;
        TagName = tagName;
    }
}

// Value Object (for audit/history)
public class PostRevision
{
    public int Version { get; private set; }
    public string ContentSnapshot { get; private set; }
    public DateTime CreatedAt { get; private set; }

    public PostRevision(int version, string contentSnapshot)
    {
        Version = version;
        ContentSnapshot = contentSnapshot;
        CreatedAt = DateTime.UtcNow;
    }
}

// Value Objects
public record PostId(Guid Value)
{
    public static PostId NewId() => new(Guid.NewGuid());
}

public record PublicationId(Guid Value);
public record AuthorId(Guid Value);
public record TagId(Guid Value);

public record PostTitle
{
    public string Value { get; }

    public PostTitle(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException("Title cannot be empty.");
        if (value.Length > 300)
            throw new ArgumentException("Title cannot exceed 300 characters.");
        
        Value = value.Trim();
    }
}

public record Slug
{
    public string Value { get; }

    public Slug(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException("Slug cannot be empty.");
        if (!System.Text.RegularExpressions.Regex.IsMatch(value, "^[a-z0-9-]+$"))
            throw new ArgumentException("Slug must contain only lowercase letters, numbers, and hyphens.");

        Value = value;
    }

    public static Slug FromTitle(string title)
    {
        var slug = title.ToLowerInvariant()
            .Replace(" ", "-")
            .Replace("_", "-");
        
        // Remove invalid characters
        slug = System.Text.RegularExpressions.Regex.Replace(slug, @"[^a-z0-9-]", "");
        
        return new Slug(slug);
    }
}

public record PostContent
{
    public string Value { get; } // JSON or HTML

    public PostContent(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException("Content cannot be empty.");

        Value = value;
    }
}

public record Excerpt
{
    public string Value { get; }

    public Excerpt(string value)
    {
        Value = value ?? string.Empty;
    }

    public static Excerpt FromContent(string content, int maxLength = 200)
    {
        if (string.IsNullOrWhiteSpace(content))
            return new Excerpt(string.Empty);

        var plain = System.Text.RegularExpressions.Regex.Replace(content, "<.*?>", string.Empty);
        var excerpt = plain.Length <= maxLength 
            ? plain 
            : plain.Substring(0, maxLength) + "...";

        return new Excerpt(excerpt);
    }
}

public enum PostStatus
{
    Draft,
    Scheduled,
    Published
}

public enum VisibilityTier
{
    Public,
    FreeSubscriber,
    PaidSubscriber
}
```

#### Domain Events

```csharp
public record PostDraftedEvent(PostId PostId, PublicationId PublicationId, AuthorId AuthorId) : DomainEvent;
public record PostPublishedEvent(PostId PostId, PublicationId PublicationId, string Title, VisibilityTier Visibility) : DomainEvent;
public record PostUpdatedEvent(PostId PostId, PublicationId PublicationId) : DomainEvent;
public record PostScheduledEvent(PostId PostId, PublicationId PublicationId, DateTime ScheduledFor) : DomainEvent;
public record PostUnpublishedEvent(PostId PostId, PublicationId PublicationId) : DomainEvent;
```

---

## Subscription Context

### Subscription Aggregate

**Aggregate Root:** `Subscription`

#### Entities & Value Objects

```csharp
// Aggregate Root
public class Subscription : AggregateRoot<SubscriptionId>
{
    public SubscriberId SubscriberId { get; private set; }
    public PublicationId PublicationId { get; private set; }
    public TierId TierId { get; private set; }
    public SubscriptionStatus Status { get; private set; }
    public TrialPeriod? TrialPeriod { get; private set; }
    public BillingCycle BillingCycle { get; private set; }
    public DateTime? CurrentPeriodEnd { get; private set; }
    public string? ExternalSubscriptionId { get; private set; } // Stripe ID
    public DateTime CreatedAt { get; private set; }
    public DateTime UpdatedAt { get; private set; }

    // Factory method
    public static Subscription Create(
        SubscriberId subscriberId,
        PublicationId publicationId,
        TierId tierId,
        BillingCycle billingCycle,
        TrialPeriod? trialPeriod = null)
    {
        var subscription = new Subscription
        {
            Id = SubscriptionId.NewId(),
            SubscriberId = subscriberId,
            PublicationId = publicationId,
            TierId = tierId,
            BillingCycle = billingCycle,
            TrialPeriod = trialPeriod,
            Status = trialPeriod != null ? SubscriptionStatus.Trialing : SubscriptionStatus.Active,
            CurrentPeriodEnd = CalculatePeriodEnd(billingCycle, trialPeriod),
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        var eventToRaise = trialPeriod != null
            ? new TrialStartedEvent(subscription.Id, subscriberId, publicationId, trialPeriod.EndDate)
            : new SubscriptionActivatedEvent(subscription.Id, subscriberId, publicationId, tierId);

        subscription.AddDomainEvent(eventToRaise);
        return subscription;
    }

    // Commands
    public void Activate(string externalSubscriptionId)
    {
        if (Status == SubscriptionStatus.Active)
            throw new DomainException("Subscription is already active.");

        Status = SubscriptionStatus.Active;
        ExternalSubscriptionId = externalSubscriptionId;
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new SubscriptionActivatedEvent(Id, SubscriberId, PublicationId, TierId));
    }

    public void Renew(DateTime newPeriodEnd)
    {
        if (Status != SubscriptionStatus.Active && Status != SubscriptionStatus.PastDue)
            throw new DomainException("Only active or past due subscriptions can be renewed.");

        Status = SubscriptionStatus.Active;
        CurrentPeriodEnd = newPeriodEnd;
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new SubscriptionRenewedEvent(Id, SubscriberId, newPeriodEnd));
    }

    public void MarkPastDue()
    {
        if (Status != SubscriptionStatus.Active)
            throw new DomainException("Only active subscriptions can become past due.");

        Status = SubscriptionStatus.PastDue;
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new SubscriptionPastDueEvent(Id, SubscriberId));
    }

    public void Cancel()
    {
        if (Status == SubscriptionStatus.Canceled)
            return; // Idempotent

        Status = SubscriptionStatus.Canceled;
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new SubscriptionCanceledEvent(Id, SubscriberId, PublicationId, CurrentPeriodEnd));
    }

    public void EndTrial()
    {
        if (Status != SubscriptionStatus.Trialing)
            throw new DomainException("Subscription is not in trial.");

        if (TrialPeriod == null || TrialPeriod.EndDate > DateTime.UtcNow)
            throw new DomainException("Trial period has not ended yet.");

        Status = SubscriptionStatus.Active;
        CurrentPeriodEnd = CalculatePeriodEnd(BillingCycle, null);
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new TrialEndedEvent(Id, SubscriberId));
    }

    public void ChangeTier(TierId newTierId, bool isUpgrade)
    {
        if (TierId == newTierId)
            return;

        var oldTierId = TierId;
        TierId = newTierId;
        UpdatedAt = DateTime.UtcNow;

        var eventToRaise = isUpgrade
            ? new SubscriptionUpgradedEvent(Id, SubscriberId, oldTierId, newTierId)
            : (DomainEvent)new SubscriptionDowngradedEvent(Id, SubscriberId, oldTierId, newTierId);

        AddDomainEvent(eventToRaise);
    }

    public bool HasAccess(VisibilityTier requiredTier)
    {
        if (Status != SubscriptionStatus.Active && Status != SubscriptionStatus.Trialing)
            return false;

        if (CurrentPeriodEnd.HasValue && CurrentPeriodEnd < DateTime.UtcNow)
            return false;

        // Simplified: assumes tier hierarchy (Free < Paid)
        return requiredTier switch
        {
            VisibilityTier.Public => true,
            VisibilityTier.FreeSubscriber => true, // Any subscription grants free access
            VisibilityTier.PaidSubscriber => true, // Assuming this is a paid tier
            _ => false
        };
    }

    private static DateTime CalculatePeriodEnd(BillingCycle billingCycle, TrialPeriod? trial)
    {
        var startDate = trial?.EndDate ?? DateTime.UtcNow;
        return billingCycle switch
        {
            BillingCycle.Monthly => startDate.AddMonths(1),
            BillingCycle.Yearly => startDate.AddYears(1),
            _ => throw new ArgumentException("Invalid billing cycle")
        };
    }

    protected override void Validate()
    {
        if (SubscriberId == null) throw new DomainException("Subscription must have a subscriber.");
        if (PublicationId == null) throw new DomainException("Subscription must belong to a publication.");
        if (TierId == null) throw new DomainException("Subscription must have a tier.");
    }
}

// Value Objects
public record SubscriptionId(Guid Value)
{
    public static SubscriptionId NewId() => new(Guid.NewGuid());
}

public record SubscriberId(Guid Value);
public record TierId(Guid Value);

public record TrialPeriod
{
    public int DurationDays { get; }
    public DateTime StartDate { get; }
    public DateTime EndDate { get; }

    public TrialPeriod(int durationDays)
    {
        if (durationDays <= 0)
            throw new ArgumentException("Trial duration must be positive.");

        DurationDays = durationDays;
        StartDate = DateTime.UtcNow;
        EndDate = StartDate.AddDays(durationDays);
    }
}

public enum SubscriptionStatus
{
    Active,
    PastDue,
    Canceled,
    Trialing
}

public enum BillingCycle
{
    Monthly,
    Yearly
}
```

#### Domain Events

```csharp
public record SubscriptionActivatedEvent(SubscriptionId SubscriptionId, SubscriberId SubscriberId, PublicationId PublicationId, TierId TierId) : DomainEvent;
public record SubscriptionRenewedEvent(SubscriptionId SubscriptionId, SubscriberId SubscriberId, DateTime NewPeriodEnd) : DomainEvent;
public record SubscriptionCanceledEvent(SubscriptionId SubscriptionId, SubscriberId SubscriberId, PublicationId PublicationId, DateTime? AccessUntil) : DomainEvent;
public record SubscriptionPastDueEvent(SubscriptionId SubscriptionId, SubscriberId SubscriberId) : DomainEvent;
public record TrialStartedEvent(SubscriptionId SubscriptionId, SubscriberId SubscriberId, PublicationId PublicationId, DateTime TrialEndDate) : DomainEvent;
public record TrialEndedEvent(SubscriptionId SubscriptionId, SubscriberId SubscriberId) : DomainEvent;
public record SubscriptionUpgradedEvent(SubscriptionId SubscriptionId, SubscriberId SubscriberId, TierId OldTierId, TierId NewTierId) : DomainEvent;
public record SubscriptionDowngradedEvent(SubscriptionId SubscriptionId, SubscriberId SubscriberId, TierId OldTierId, TierId NewTierId) : DomainEvent;
```

---

## Payment Context

### Payment Aggregate

**Aggregate Root:** `Payment`

```csharp
public class Payment : AggregateRoot<PaymentId>
{
    public SubscriptionId SubscriptionId { get; private set; }
    public Money Amount { get; private set; }
    public PaymentProvider Provider { get; private set; }
    public PaymentStatus Status { get; private set; }
    public string? ExternalPaymentId { get; private set; }
    public string? FailureReason { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public DateTime UpdatedAt { get; private set; }

    public static Payment Initiate(
        SubscriptionId subscriptionId,
        Money amount,
        PaymentProvider provider)
    {
        var payment = new Payment
        {
            Id = PaymentId.NewId(),
            SubscriptionId = subscriptionId,
            Amount = amount,
            Provider = provider,
            Status = PaymentStatus.Pending,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        payment.AddDomainEvent(new PaymentInitiatedEvent(payment.Id, subscriptionId, amount));
        return payment;
    }

    public void MarkSucceeded(string externalPaymentId)
    {
        if (Status == PaymentStatus.Succeeded)
            return; // Idempotent

        Status = PaymentStatus.Succeeded;
        ExternalPaymentId = externalPaymentId;
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new PaymentSucceededEvent(Id, SubscriptionId, Amount));
    }

    public void MarkFailed(string failureReason)
    {
        if (Status == PaymentStatus.Failed)
            return;

        Status = PaymentStatus.Failed;
        FailureReason = failureReason;
        UpdatedAt = DateTime.UtcNow;

        AddDomainEvent(new PaymentFailedEvent(Id, SubscriptionId, failureReason));
    }

    protected override void Validate()
    {
        if (Amount == null || Amount.AmountInCents <= 0)
            throw new DomainException("Payment amount must be positive.");
    }
}

// Value Objects
public record PaymentId(Guid Value)
{
    public static PaymentId NewId() => new(Guid.NewGuid());
}

public record Money
{
    public int AmountInCents { get; }
    public string Currency { get; }

    public Money(int amountInCents, string currency)
    {
        if (amountInCents < 0)
            throw new ArgumentException("Amount cannot be negative.");
        if (string.IsNullOrWhiteSpace(currency) || currency.Length != 3)
            throw new ArgumentException("Currency must be a 3-letter ISO code.");

        AmountInCents = amountInCents;
        Currency = currency.ToUpperInvariant();
    }

    public decimal AmountInUnits => AmountInCents / 100m;
}

public enum PaymentStatus
{
    Pending,
    Succeeded,
    Failed,
    Refunded
}

public enum PaymentProvider
{
    Stripe,
    PayPal
}

// Domain Events
public record PaymentInitiatedEvent(PaymentId PaymentId, SubscriptionId SubscriptionId, Money Amount) : DomainEvent;
public record PaymentSucceededEvent(PaymentId PaymentId, SubscriptionId SubscriptionId, Money Amount) : DomainEvent;
public record PaymentFailedEvent(PaymentId PaymentId, SubscriptionId SubscriptionId, string Reason) : DomainEvent;
```

---

## Shared Kernel

### Base Classes

```csharp
public abstract class Entity<TId> where TId : notnull
{
    public TId Id { get; protected set; }

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
}

public abstract class AggregateRoot<TId> : Entity<TId> where TId : notnull
{
    private readonly List<DomainEvent> _domainEvents = new();

    public IReadOnlyCollection<DomainEvent> DomainEvents => _domainEvents.AsReadOnly();

    protected void AddDomainEvent(DomainEvent domainEvent)
    {
        _domainEvents.Add(domainEvent);
    }

    public void ClearDomainEvents()
    {
        _domainEvents.Clear();
    }

    protected abstract void Validate();
}

public abstract record DomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTime OccurredAt { get; } = DateTime.UtcNow;
}

public class DomainException : Exception
{
    public DomainException(string message) : base(message) { }
}
```

---

## Frugal Implementation Notes

### Single Database, Multiple Schemas
- Start with one relational database (PostgreSQL or MySQL recommended)
- Separate schema per bounded context: `Publishing`, `Subscription`, `Payment`
- Aggregate roots own their tables, no foreign keys across schemas
- Use views for cross-context queries (read models)

### In-Process Event Bus (Phase 1)
- Use custom event dispatcher or open-source library for domain event handling
- Events published synchronously within same transaction
- Upgrade to message broker (RabbitMQ, Kafka, NATS) when splitting into microservices

### Repository Pattern per Aggregate
```csharp
public interface IPostRepository
{
    Task<Post?> GetByIdAsync(PostId id, CancellationToken ct = default);
    Task<Post?> GetBySlugAsync(PublicationId publicationId, Slug slug, CancellationToken ct = default);
    Task AddAsync(Post post, CancellationToken ct = default);
    Task UpdateAsync(Post post, CancellationToken ct = default);
    Task DeleteAsync(PostId id, CancellationToken ct = default);
}
```

### ORM Configuration
- One database context per bounded context
- Use owned entities or embedded objects for value objects
- Use table splitting for aggregate root + value objects in same table when appropriate
- Enable query filters for soft deletes and multi-tenancy
- Examples: Entity Framework Core (.NET), Hibernate (Java), SQLAlchemy (Python), TypeORM (TypeScript)

---

## Next Document

**SPEC-4: Application Services & Use Cases** - CQRS Commands/Queries mapped to these aggregates.

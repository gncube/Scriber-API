# SPEC-4: Application Layer - CQRS Commands & Queries

## Overview

This document defines the Application Layer for Scriber API, implementing CQRS patterns using our custom mediator. The Application Layer orchestrates domain logic, validates requests, and coordinates workflows.

**Principles:**
- Commands modify state, queries read state (CQRS)
- Use cases independent of delivery mechanism (HTTP, gRPC, etc.)
- DTOs for data transfer (never expose domain entities)
- Input validation using validation library (FluentValidation, class-validator, Joi, etc.)
- Pipeline behaviors for cross-cutting concerns

---

## Layer Structure

```
Scriber.Application/
├── Common/
│   ├── Behaviors/               # Pipeline behaviors
│   ├── Exceptions/              # Application exceptions
│   ├── Interfaces/              # Repository & service abstractions
│   ├── Mapping/                 # AutoMapper profiles
│   ├── Messaging/               # Mediator interfaces
│   └── Models/                  # Shared DTOs
├── Publishing/
│   ├── Commands/
│   │   ├── CreatePost/
│   │   │   ├── CreatePostCommand.cs
│   │   │   ├── CreatePostCommandHandler.cs
│   │   │   └── CreatePostCommandValidator.cs
│   │   ├── PublishPost/
│   │   └── UpdatePost/
│   ├── Queries/
│   │   ├── GetPost/
│   │   ├── GetPostList/
│   │   └── SearchPosts/
│   ├── EventHandlers/           # Domain event handlers
│   └── DTOs/
├── Subscriptions/
│   ├── Commands/
│   ├── Queries/
│   └── EventHandlers/
└── Payments/
    ├── Commands/
    ├── Queries/
    └── EventHandlers/
```

---

## Publishing Context - Commands

### 1. Create Post Command

```csharp
namespace Scriber.Application.Publishing.Commands.CreatePost;

using Scriber.Application.Common.Messaging;

public record CreatePostCommand : ICommand<Guid>
{
    public Guid PublicationId { get; init; }
    public string Title { get; init; } = string.Empty;
    public string Content { get; init; } = string.Empty;
    public string Visibility { get; init; } = "public";
    public List<string> Tags { get; init; } = new();
}

public class CreatePostCommandValidator : AbstractValidator<CreatePostCommand>
{
    public CreatePostCommandValidator()
    {
        RuleFor(x => x.PublicationId)
            .NotEmpty()
            .WithMessage("Publication ID is required");

        RuleFor(x => x.Title)
            .NotEmpty()
            .WithMessage("Title is required")
            .MaximumLength(300)
            .WithMessage("Title cannot exceed 300 characters");

        RuleFor(x => x.Content)
            .NotEmpty()
            .WithMessage("Content is required");

        RuleFor(x => x.Visibility)
            .Must(v => new[] { "public", "free_subscriber", "paid_subscriber" }.Contains(v))
            .WithMessage("Invalid visibility tier");

        RuleFor(x => x.Tags)
            .Must(tags => tags == null || tags.Count <= 10)
            .WithMessage("Maximum 10 tags allowed");
    }
}

public class CreatePostCommandHandler : ICommandHandler<CreatePostCommand, Guid>
{
    private readonly IPublishingDbContext _context;
    private readonly IPostRepository _postRepository;
    private readonly ICurrentUserService _currentUser;
    private readonly ILogger<CreatePostCommandHandler> _logger;

    public CreatePostCommandHandler(
        IPublishingDbContext context,
        IPostRepository postRepository,
        ICurrentUserService currentUser,
        ILogger<CreatePostCommandHandler> logger)
    {
        _context = context;
        _postRepository = postRepository;
        _currentUser = currentUser;
        _logger = logger;
    }

    public async Task<Guid> Handle(CreatePostCommand request, CancellationToken cancellationToken)
    {
        // Verify publication exists and user has access
        var publication = await _context.Publications
            .FirstOrDefaultAsync(p => p.Id == new PublicationId(request.PublicationId), cancellationToken);

        if (publication == null)
            throw new NotFoundException(nameof(Publication), request.PublicationId);

        var currentUserId = _currentUser.UserId 
            ?? throw new UnauthorizedException("User must be authenticated");

        // Check user has author/editor role for this publication
        if (!await _currentUser.HasRoleAsync("Author") && !await _currentUser.HasRoleAsync("Editor"))
            throw new ForbiddenException("User must be an author or editor");

        // Create domain entity
        var post = Post.CreateDraft(
            new PublicationId(request.PublicationId),
            new AuthorId(currentUserId),
            new PostTitle(request.Title),
            new PostContent(request.Content),
            Enum.Parse<VisibilityTier>(request.Visibility, ignoreCase: true));

        // Add tags
        foreach (var tagName in request.Tags ?? new List<string>())
        {
            var tag = await GetOrCreateTagAsync(request.PublicationId, tagName, cancellationToken);
            post.AddTag(tag.Id, tag.Name);
        }

        // Persist
        await _postRepository.AddAsync(post, cancellationToken);
        await _context.SaveChangesAsync(cancellationToken);

        _logger.LogInformation("Created draft post {PostId} for publication {PublicationId}", 
            post.Id.Value, request.PublicationId);

        return post.Id.Value;
    }

    private async Task<Tag> GetOrCreateTagAsync(
        Guid publicationId, 
        string tagName, 
        CancellationToken cancellationToken)
    {
        var normalizedName = tagName.Trim().ToLowerInvariant();
        var slug = Slug.FromTitle(normalizedName);

        var existingTag = await _context.Tags
            .FirstOrDefaultAsync(t => 
                t.PublicationId == new PublicationId(publicationId) && 
                t.Slug == slug, 
                cancellationToken);

        if (existingTag != null)
            return existingTag;

        var newTag = new Tag(
            TagId.NewId(),
            new PublicationId(publicationId),
            normalizedName,
            slug);

        _context.Tags.Add(newTag);
        return newTag;
    }
}
```

### 2. Publish Post Command

```csharp
namespace Scriber.Application.Publishing.Commands.PublishPost;

using Scriber.Application.Common.Messaging;

public record PublishPostCommand(Guid PostId) : ICommand;

public class PublishPostCommandValidator : AbstractValidator<PublishPostCommand>
{
    public PublishPostCommandValidator()
    {
        RuleFor(x => x.PostId)
            .NotEmpty()
            .WithMessage("Post ID is required");
    }
}

public class PublishPostCommandHandler : ICommandHandler<PublishPostCommand>
{
    private readonly IPostRepository _postRepository;
    private readonly IMediator _mediator;
    private readonly ICurrentUserService _currentUser;
    private readonly ILogger<PublishPostCommandHandler> _logger;

    public PublishPostCommandHandler(
        IPostRepository postRepository,
        IMediator mediator,
        ICurrentUserService currentUser,
        ILogger<PublishPostCommandHandler> logger)
    {
        _postRepository = postRepository;
        _mediator = mediator;
        _currentUser = currentUser;
        _logger = logger;
    }

    public async Task<Unit> Handle(PublishPostCommand request, CancellationToken cancellationToken)
    {
        var post = await _postRepository.GetByIdAsync(new PostId(request.PostId), cancellationToken);

        if (post == null)
            throw new NotFoundException(nameof(Post), request.PostId);

        // Authorization check
        var currentUserId = _currentUser.UserId 
            ?? throw new UnauthorizedException("User must be authenticated");

        if (post.AuthorId.Value != currentUserId && !await _currentUser.HasRoleAsync("Editor"))
            throw new ForbiddenException("Only the author or an editor can publish this post");

        // Domain logic
        post.Publish();

        // Save changes (will dispatch domain events via DbContext.SaveChangesAsync)
        await _postRepository.UpdateAsync(post, cancellationToken);

        _logger.LogInformation("Published post {PostId}", request.PostId);

        return Unit.Value;
    }
}
```

### 3. Update Post Command

```csharp
namespace Scriber.Application.Publishing.Commands.UpdatePost;

using Scriber.Application.Common.Messaging;

public record UpdatePostCommand : ICommand
{
    public Guid PostId { get; init; }
    public string Title { get; init; } = string.Empty;
    public string Content { get; init; } = string.Empty;
    public string Visibility { get; init; } = string.Empty;
    public List<string> Tags { get; init; } = new();
}

public class UpdatePostCommandValidator : AbstractValidator<UpdatePostCommand>
{
    public UpdatePostCommandValidator()
    {
        RuleFor(x => x.PostId).NotEmpty();
        RuleFor(x => x.Title).NotEmpty().MaximumLength(300);
        RuleFor(x => x.Content).NotEmpty();
        RuleFor(x => x.Visibility)
            .Must(v => new[] { "public", "free_subscriber", "paid_subscriber" }.Contains(v));
    }
}

public class UpdatePostCommandHandler : ICommandHandler<UpdatePostCommand>
{
    private readonly IPostRepository _postRepository;
    private readonly IPublishingDbContext _context;
    private readonly ICurrentUserService _currentUser;

    public UpdatePostCommandHandler(
        IPostRepository postRepository,
        IPublishingDbContext context,
        ICurrentUserService currentUser)
    {
        _postRepository = postRepository;
        _context = context;
        _currentUser = currentUser;
    }

    public async Task<Unit> Handle(UpdatePostCommand request, CancellationToken cancellationToken)
    {
        var post = await _postRepository.GetByIdAsync(new PostId(request.PostId), cancellationToken);

        if (post == null)
            throw new NotFoundException(nameof(Post), request.PostId);

        // Authorization
        var currentUserId = _currentUser.UserId ?? throw new UnauthorizedException();
        if (post.AuthorId.Value != currentUserId && !await _currentUser.HasRoleAsync("Editor"))
            throw new ForbiddenException("Only the author or editor can update this post");

        // Update domain entity
        post.UpdateContent(
            new PostTitle(request.Title),
            new PostContent(request.Content),
            Enum.Parse<VisibilityTier>(request.Visibility, ignoreCase: true));

        // Update tags (simple approach: clear and re-add)
        post.ClearTags();
        foreach (var tagName in request.Tags ?? new List<string>())
        {
            var tag = await GetOrCreateTagAsync(post.PublicationId, tagName, cancellationToken);
            post.AddTag(tag.Id, tag.Name);
        }

        await _postRepository.UpdateAsync(post, cancellationToken);

        return Unit.Value;
    }

    private async Task<Tag> GetOrCreateTagAsync(PublicationId publicationId, string tagName, CancellationToken ct)
    {
        // Same implementation as CreatePostCommandHandler
        // Consider extracting to a shared service
        throw new NotImplementedException("Extract to ITagService");
    }
}
```

### 4. Schedule Post Command

```csharp
namespace Scriber.Application.Publishing.Commands.SchedulePost;

using Scriber.Application.Common.Messaging;

public record SchedulePostCommand(Guid PostId, DateTime ScheduledFor) : ICommand;

public class SchedulePostCommandValidator : AbstractValidator<SchedulePostCommand>
{
    public SchedulePostCommandValidator()
    {
        RuleFor(x => x.PostId).NotEmpty();
        RuleFor(x => x.ScheduledFor)
            .GreaterThan(DateTime.UtcNow)
            .WithMessage("Scheduled time must be in the future");
    }
}

public class SchedulePostCommandHandler : ICommandHandler<SchedulePostCommand>
{
    private readonly IPostRepository _postRepository;
    private readonly ICurrentUserService _currentUser;

    public SchedulePostCommandHandler(
        IPostRepository postRepository,
        ICurrentUserService currentUser)
    {
        _postRepository = postRepository;
        _currentUser = currentUser;
    }

    public async Task<Unit> Handle(SchedulePostCommand request, CancellationToken cancellationToken)
    {
        var post = await _postRepository.GetByIdAsync(new PostId(request.PostId), cancellationToken);

        if (post == null)
            throw new NotFoundException(nameof(Post), request.PostId);

        // Authorization
        var currentUserId = _currentUser.UserId ?? throw new UnauthorizedException();
        if (post.AuthorId.Value != currentUserId && !await _currentUser.HasRoleAsync("Editor"))
            throw new ForbiddenException();

        // Schedule
        post.Schedule(request.ScheduledFor);

        await _postRepository.UpdateAsync(post, cancellationToken);

        return Unit.Value;
    }
}
```

---

## Publishing Context - Queries

### 1. Get Post by Slug Query

```csharp
namespace Scriber.Application.Publishing.Queries.GetPost;

using Scriber.Application.Common.Messaging;
using Scriber.Application.Publishing.DTOs;

public record GetPostBySlugQuery(string PublicationSlug, string PostSlug) : IQuery<PostDetailDto>;

public class GetPostBySlugQueryHandler : IQueryHandler<GetPostBySlugQuery, PostDetailDto>
{
    private readonly IPublishingDbContext _context;
    private readonly ICurrentUserService _currentUser;
    private readonly ISubscriptionService _subscriptionService;

    public GetPostBySlugQueryHandler(
        IPublishingDbContext context,
        ICurrentUserService currentUser,
        ISubscriptionService subscriptionService)
    {
        _context = context;
        _currentUser = currentUser;
        _subscriptionService = subscriptionService;
    }

    public async Task<PostDetailDto> Handle(GetPostBySlugQuery request, CancellationToken cancellationToken)
    {
        var post = await _context.Posts
            .Include(p => p.Publication)
            .Include(p => p.Tags)
            .AsNoTracking()
            .FirstOrDefaultAsync(p =>
                p.Publication.Slug == new Slug(request.PublicationSlug) &&
                p.Slug == new Slug(request.PostSlug) &&
                p.Status == PostStatus.Published,
                cancellationToken);

        if (post == null)
            throw new NotFoundException(nameof(Post), request.PostSlug);

        // Check access permissions
        var hasAccess = await CheckAccessAsync(post, cancellationToken);

        return new PostDetailDto
        {
            Id = post.Id.Value,
            Title = post.Title.Value,
            Slug = post.Slug.Value,
            Content = hasAccess ? post.Content.Value : null, // Paywall enforcement
            Excerpt = post.Excerpt.Value,
            Visibility = post.Visibility.ToString(),
            PublishedAt = post.PublishedAt,
            Author = new AuthorDto
            {
                Id = post.AuthorId.Value,
                DisplayName = post.Author?.DisplayName ?? "Unknown"
            },
            Tags = post.Tags.Select(t => new TagDto
            {
                Id = t.TagId.Value,
                Name = t.TagName
            }).ToList(),
            IsPaywalled = !hasAccess,
            RequiredTier = !hasAccess ? post.Visibility.ToString() : null
        };
    }

    private async Task<bool> CheckAccessAsync(Post post, CancellationToken cancellationToken)
    {
        // Public content is always accessible
        if (post.Visibility == VisibilityTier.Public)
            return true;

        // User must be authenticated for subscriber-only content
        var userId = _currentUser.UserId;
        if (userId == null)
            return false;

        // Check if user has active subscription with required tier
        return await _subscriptionService.HasAccessAsync(
            userId.Value,
            post.PublicationId,
            post.Visibility,
            cancellationToken);
    }
}
```

### 2. Get Post List Query

```csharp
namespace Scriber.Application.Publishing.Queries.GetPostList;

using Scriber.Application.Common.Messaging;
using Scriber.Application.Common.Models;
using Scriber.Application.Publishing.DTOs;

public record GetPostListQuery : IQuery<PaginatedList<PostSummaryDto>>
{
    public string PublicationSlug { get; init; } = string.Empty;
    public string? Tag { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
}

public class GetPostListQueryValidator : AbstractValidator<GetPostListQuery>
{
    public GetPostListQueryValidator()
    {
        RuleFor(x => x.PublicationSlug).NotEmpty();
        RuleFor(x => x.Page).GreaterThan(0);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 100);
    }
}

public class GetPostListQueryHandler : IQueryHandler<GetPostListQuery, PaginatedList<PostSummaryDto>>
{
    private readonly IPublishingDbContext _context;

    public GetPostListQueryHandler(IPublishingDbContext context)
    {
        _context = context;
    }

    public async Task<PaginatedList<PostSummaryDto>> Handle(
        GetPostListQuery request,
        CancellationToken cancellationToken)
    {
        var query = _context.Posts
            .Include(p => p.Publication)
            .Include(p => p.Tags)
            .AsNoTracking()
            .Where(p => p.Publication.Slug == new Slug(request.PublicationSlug))
            .Where(p => p.Status == PostStatus.Published)
            .OrderByDescending(p => p.PublishedAt);

        // Filter by tag if specified
        if (!string.IsNullOrWhiteSpace(request.Tag))
        {
            query = query.Where(p => p.Tags.Any(t => t.TagName == request.Tag.ToLowerInvariant()));
        }

        var totalCount = await query.CountAsync(cancellationToken);

        var posts = await query
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(p => new PostSummaryDto
            {
                Id = p.Id.Value,
                Title = p.Title.Value,
                Slug = p.Slug.Value,
                Excerpt = p.Excerpt.Value,
                Visibility = p.Visibility.ToString(),
                PublishedAt = p.PublishedAt,
                Author = new AuthorDto
                {
                    Id = p.AuthorId.Value,
                    DisplayName = p.Author.DisplayName
                },
                Tags = p.Tags.Select(t => new TagDto
                {
                    Id = t.TagId.Value,
                    Name = t.TagName
                }).ToList()
            })
            .ToListAsync(cancellationToken);

        return new PaginatedList<PostSummaryDto>(
            posts,
            totalCount,
            request.Page,
            request.PageSize);
    }
}
```

### 3. Search Posts Query

```csharp
namespace Scriber.Application.Publishing.Queries.SearchPosts;

using Scriber.Application.Common.Messaging;
using Scriber.Application.Common.Models;
using Scriber.Application.Publishing.DTOs;

public record SearchPostsQuery(string SearchTerm, int Page = 1, int PageSize = 20) 
    : IQuery<PaginatedList<PostSummaryDto>>;

public class SearchPostsQueryHandler : IQueryHandler<SearchPostsQuery, PaginatedList<PostSummaryDto>>
{
    private readonly IPublishingDbContext _context;

    public SearchPostsQueryHandler(IPublishingDbContext context)
    {
        _context = context;
    }

    public async Task<PaginatedList<PostSummaryDto>> Handle(
        SearchPostsQuery request,
        CancellationToken cancellationToken)
    {
        // Use PostgreSQL full-text search (already indexed in database)
        var searchVector = EF.Functions.ToTsVector("english", 
            EF.Functions.Concat(
                EF.Functions.Coalesce(EF.Property<string>(null, "Title"), ""),
                " ",
                EF.Functions.Coalesce(EF.Property<string>(null, "Content"), "")));

        var searchQuery = EF.Functions.ToTsQuery("english", request.SearchTerm);

        var query = _context.Posts
            .AsNoTracking()
            .Where(p => p.Status == PostStatus.Published)
            .Where(p => searchVector.Matches(searchQuery))
            .OrderByDescending(p => p.PublishedAt);

        var totalCount = await query.CountAsync(cancellationToken);

        var posts = await query
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(p => new PostSummaryDto
            {
                Id = p.Id.Value,
                Title = p.Title.Value,
                Slug = p.Slug.Value,
                Excerpt = p.Excerpt.Value,
                Visibility = p.Visibility.ToString(),
                PublishedAt = p.PublishedAt
            })
            .ToListAsync(cancellationToken);

        return new PaginatedList<PostSummaryDto>(posts, totalCount, request.Page, request.PageSize);
    }
}
```

---

## Subscription Context - Commands

### 1. Subscribe Command

```csharp
namespace Scriber.Application.Subscriptions.Commands.Subscribe;

using Scriber.Application.Common.Messaging;

public record SubscribeCommand : ICommand<Guid>
{
    public Guid PublicationId { get; init; }
    public string Email { get; init; } = string.Empty;
    public Guid TierId { get; init; }
    public string? PaymentMethodToken { get; init; }
}

public class SubscribeCommandValidator : AbstractValidator<SubscribeCommand>
{
    public SubscribeCommandValidator()
    {
        RuleFor(x => x.PublicationId).NotEmpty();
        RuleFor(x => x.Email).NotEmpty().EmailAddress();
        RuleFor(x => x.TierId).NotEmpty();
    }
}

public class SubscribeCommandHandler : ICommandHandler<SubscribeCommand, Guid>
{
    private readonly ISubscriptionRepository _subscriptionRepository;
    private readonly ISubscriberRepository _subscriberRepository;
    private readonly IPublishingDbContext _context;
    private readonly IPaymentService _paymentService;
    private readonly ILogger<SubscribeCommandHandler> _logger;

    public SubscribeCommandHandler(
        ISubscriptionRepository subscriptionRepository,
        ISubscriberRepository subscriberRepository,
        IPublishingDbContext context,
        IPaymentService paymentService,
        ILogger<SubscribeCommandHandler> logger)
    {
        _subscriptionRepository = subscriptionRepository;
        _subscriberRepository = subscriberRepository;
        _context = context;
        _paymentService = paymentService;
        _logger = logger;
    }

    public async Task<Guid> Handle(SubscribeCommand request, CancellationToken cancellationToken)
    {
        // Get or create subscriber
        var subscriber = await _subscriberRepository.GetByEmailAsync(
            new PublicationId(request.PublicationId),
            request.Email,
            cancellationToken);

        if (subscriber == null)
        {
            subscriber = Subscriber.Create(
                new PublicationId(request.PublicationId),
                request.Email);
            await _subscriberRepository.AddAsync(subscriber, cancellationToken);
        }

        // Check for existing active subscription
        var existingSubscription = await _subscriptionRepository
            .GetActiveSubscriptionAsync(subscriber.Id, cancellationToken);

        if (existingSubscription != null)
            throw new DomainException("Subscriber already has an active subscription");

        // Get tier details
        var tier = await _context.SubscriptionTiers
            .FirstOrDefaultAsync(t => t.Id == new TierId(request.TierId), cancellationToken);

        if (tier == null)
            throw new NotFoundException(nameof(SubscriptionTier), request.TierId);

        // Create subscription
        var trialPeriod = tier.TrialDays > 0 ? new TrialPeriod(tier.TrialDays) : null;

        var subscription = Subscription.Create(
            subscriber.Id,
            new PublicationId(request.PublicationId),
            tier.Id,
            tier.BillingCycle,
            trialPeriod);

        // If paid tier and not in trial, initiate payment
        if (tier.PriceCents > 0 && trialPeriod == null)
        {
            var paymentResult = await _paymentService.CreateSubscriptionAsync(
                subscription.Id,
                tier.StripePriceId!,
                request.PaymentMethodToken!,
                cancellationToken);

            if (!paymentResult.Succeeded)
                throw new DomainException($"Payment failed: {paymentResult.ErrorMessage}");

            subscription.Activate(paymentResult.ExternalSubscriptionId!);
        }
        else
        {
            // Free tier or trial - activate immediately
            subscription.Activate(null);
        }

        await _subscriptionRepository.AddAsync(subscription, cancellationToken);

        _logger.LogInformation(
            "Created subscription {SubscriptionId} for subscriber {SubscriberId}",
            subscription.Id.Value, subscriber.Id.Value);

        return subscription.Id.Value;
    }
}
```

### 2. Cancel Subscription Command

```csharp
namespace Scriber.Application.Subscriptions.Commands.CancelSubscription;

using Scriber.Application.Common.Messaging;

public record CancelSubscriptionCommand(Guid SubscriptionId) : ICommand;

public class CancelSubscriptionCommandHandler : ICommandHandler<CancelSubscriptionCommand>
{
    private readonly ISubscriptionRepository _subscriptionRepository;
    private readonly IPaymentService _paymentService;
    private readonly ICurrentUserService _currentUser;

    public CancelSubscriptionCommandHandler(
        ISubscriptionRepository subscriptionRepository,
        IPaymentService paymentService,
        ICurrentUserService currentUser)
    {
        _subscriptionRepository = subscriptionRepository;
        _paymentService = paymentService;
        _currentUser = currentUser;
    }

    public async Task<Unit> Handle(CancelSubscriptionCommand request, CancellationToken cancellationToken)
    {
        var subscription = await _subscriptionRepository.GetByIdAsync(
            new SubscriptionId(request.SubscriptionId),
            cancellationToken);

        if (subscription == null)
            throw new NotFoundException(nameof(Subscription), request.SubscriptionId);

        // Authorization: user must own this subscription
        var currentUserId = _currentUser.UserId ?? throw new UnauthorizedException();
        var subscriber = await _subscriptionRepository.GetSubscriberAsync(subscription.SubscriberId, cancellationToken);
        
        if (subscriber.UserId?.Value != currentUserId)
            throw new ForbiddenException("You can only cancel your own subscription");

        // Cancel in payment provider if external subscription exists
        if (!string.IsNullOrEmpty(subscription.ExternalSubscriptionId))
        {
            await _paymentService.CancelSubscriptionAsync(
                subscription.ExternalSubscriptionId,
                cancellationToken);
        }

        // Cancel in domain
        subscription.Cancel();

        await _subscriptionRepository.UpdateAsync(subscription, cancellationToken);

        return Unit.Value;
    }
}
```

---

## DTOs (Data Transfer Objects)

### Publishing DTOs

```csharp
namespace Scriber.Application.Publishing.DTOs;

public record PostDetailDto
{
    public Guid Id { get; init; }
    public string Title { get; init; } = string.Empty;
    public string Slug { get; init; } = string.Empty;
    public string? Content { get; init; } // Null if paywalled
    public string Excerpt { get; init; } = string.Empty;
    public string Visibility { get; init; } = string.Empty;
    public DateTime? PublishedAt { get; init; }
    public AuthorDto Author { get; init; } = null!;
    public List<TagDto> Tags { get; init; } = new();
    public bool IsPaywalled { get; init; }
    public string? RequiredTier { get; init; }
}

public record PostSummaryDto
{
    public Guid Id { get; init; }
    public string Title { get; init; } = string.Empty;
    public string Slug { get; init; } = string.Empty;
    public string Excerpt { get; init; } = string.Empty;
    public string Visibility { get; init; } = string.Empty;
    public DateTime? PublishedAt { get; init; }
    public AuthorDto? Author { get; init; }
    public List<TagDto> Tags { get; init; } = new();
}

public record AuthorDto
{
    public Guid Id { get; init; }
    public string DisplayName { get; init; } = string.Empty;
}

public record TagDto
{
    public Guid Id { get; init; }
    public string Name { get; init; } = string.Empty;
}
```

### Subscription DTOs

```csharp
namespace Scriber.Application.Subscriptions.DTOs;

public record SubscriptionDto
{
    public Guid Id { get; init; }
    public string Status { get; init; } = string.Empty;
    public TierDto Tier { get; init; } = null!;
    public DateTime? CurrentPeriodEnd { get; init; }
    public bool IsTrialing { get; init; }
    public DateTime? TrialEndDate { get; init; }
}

public record TierDto
{
    public Guid Id { get; init; }
    public string Name { get; init; } = string.Empty;
    public decimal Price { get; init; }
    public string BillingPeriod { get; init; } = string.Empty;
}
```

---

## Common Models

### Paginated List

```csharp
namespace Scriber.Application.Common.Models;

public class PaginatedList<T>
{
    public List<T> Items { get; }
    public int TotalCount { get; }
    public int Page { get; }
    public int PageSize { get; }
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
    public bool HasPreviousPage => Page > 1;
    public bool HasNextPage => Page < TotalPages;

    public PaginatedList(List<T> items, int totalCount, int page, int pageSize)
    {
        Items = items;
        TotalCount = totalCount;
        Page = page;
        PageSize = pageSize;
    }
}
```

### Result Pattern

```csharp
namespace Scriber.Application.Common.Models;

public class Result
{
    public bool Succeeded { get; init; }
    public string? ErrorMessage { get; init; }
    public List<string> Errors { get; init; } = new();

    public static Result Success() => new() { Succeeded = true };
    public static Result Failure(string error) => new() { Succeeded = false, ErrorMessage = error };
    public static Result Failure(List<string> errors) => new() { Succeeded = false, Errors = errors };
}

public class Result<T> : Result
{
    public T? Data { get; init; }

    public static Result<T> Success(T data) => new() { Succeeded = true, Data = data };
    public new static Result<T> Failure(string error) => new() { Succeeded = false, ErrorMessage = error };
}
```

---

## Common Exceptions

```csharp
namespace Scriber.Application.Common.Exceptions;

public class NotFoundException : Exception
{
    public NotFoundException(string entityName, object key)
        : base($"Entity '{entityName}' with key '{key}' was not found.")
    {
    }
}

public class UnauthorizedException : Exception
{
    public UnauthorizedException(string? message = "User is not authenticated")
        : base(message)
    {
    }
}

public class ForbiddenException : Exception
{
    public ForbiddenException(string? message = "User does not have permission to perform this action")
        : base(message)
    {
    }
}

public class ValidationException : Exception
{
    public List<string> Errors { get; }

    public ValidationException(List<string> errors)
        : base("One or more validation errors occurred.")
    {
        Errors = errors;
    }
}
```

---

## Domain Event Handlers

### Send Email on Post Published

```csharp
namespace Scriber.Application.Publishing.EventHandlers;

using Scriber.Application.Common.Messaging;
using Scriber.Domain.Publishing.Events;

public class SendEmailOnPostPublishedHandler : INotificationHandler<PostPublishedEvent>
{
    private readonly ISubscriberRepository _subscriberRepository;
    private readonly IEmailService _emailService;
    private readonly ILogger<SendEmailOnPostPublishedHandler> _logger;

    public SendEmailOnPostPublishedHandler(
        ISubscriberRepository subscriberRepository,
        IEmailService emailService,
        ILogger<SendEmailOnPostPublishedHandler> logger)
    {
        _subscriberRepository = subscriberRepository;
        _emailService = emailService;
        _logger = logger;
    }

    public async Task Handle(PostPublishedEvent notification, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Sending emails for published post {PostId}", notification.PostId);

        // Get eligible subscribers based on visibility tier
        var subscribers = await _subscriberRepository.GetEligibleSubscribersAsync(
            notification.PublicationId,
            notification.Visibility,
            cancellationToken);

        if (!subscribers.Any())
        {
            _logger.LogInformation("No eligible subscribers for post {PostId}", notification.PostId);
            return;
        }

        // Queue email campaign (async processing)
        await _emailService.QueueNewPostEmailAsync(
            notification.PublicationId,
            notification.PostId,
            notification.Title,
            subscribers.Select(s => s.Email).ToList(),
            cancellationToken);

        _logger.LogInformation(
            "Queued new post email for {SubscriberCount} subscribers",
            subscribers.Count);
    }
}
```

---

## Service Interfaces

```csharp
namespace Scriber.Application.Common.Interfaces;

public interface ICurrentUserService
{
    Guid? UserId { get; }
    string? Email { get; }
    Task<bool> HasRoleAsync(string role);
    Task<bool> IsInPublicationAsync(Guid publicationId);
}

public interface IEmailService
{
    Task QueueNewPostEmailAsync(
        PublicationId publicationId,
        PostId postId,
        string postTitle,
        List<string> recipientEmails,
        CancellationToken cancellationToken);

    Task SendWelcomeEmailAsync(string email, CancellationToken cancellationToken);
}

public interface IPaymentService
{
    Task<PaymentResult> CreateSubscriptionAsync(
        SubscriptionId subscriptionId,
        string stripePriceId,
        string paymentMethodToken,
        CancellationToken cancellationToken);

    Task CancelSubscriptionAsync(string externalSubscriptionId, CancellationToken cancellationToken);
}

public interface ISubscriptionService
{
    Task<bool> HasAccessAsync(
        Guid userId,
        PublicationId publicationId,
        VisibilityTier requiredTier,
        CancellationToken cancellationToken);
}

public record PaymentResult
{
    public bool Succeeded { get; init; }
    public string? ExternalSubscriptionId { get; init; }
    public string? ErrorMessage { get; init; }
}
```

---

## Dependency Injection Setup

```csharp
namespace Scriber.Application;

using FluentValidation;
using Microsoft.Extensions.DependencyInjection;
using Scriber.Application.Common.Behaviors;
using System.Reflection;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        var assembly = Assembly.GetExecutingAssembly();

        // Register validators
        services.AddValidatorsFromAssembly(assembly);

        // Register mediator (from SPEC-2.2)
        services.AddMediator(assembly);

        return services;
    }
}
```

---

## Summary

This application layer provides:

✅ **CQRS Pattern** - Clear separation of commands (write) and queries (read)  
✅ **Validation** - FluentValidation on all commands  
✅ **Authorization** - Role-based and resource-based checks  
✅ **DTOs** - No domain entities exposed to API  
✅ **Domain Events** - Handled via custom mediator  
✅ **Paywall Logic** - Subscription-based access control  
✅ **Testability** - Clean dependencies, easy to mock  
✅ **Frugal** - No expensive libraries, all custom code  

**Next:** SPEC-5 (Infrastructure Layer with EF Core implementations)

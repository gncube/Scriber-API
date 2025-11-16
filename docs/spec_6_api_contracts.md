# SPEC-6: API Contracts - REST Endpoints & OpenAPI

## Overview

This document defines the REST API contracts for Scriber API, including endpoints, request/response DTOs, validation, authentication, and OpenAPI/Swagger documentation.

**Principles:**
- RESTful design (resources, verbs, status codes)
- API versioning via URL path (/api/v1/)
- JWT bearer token authentication
- Consistent error responses
- OpenAPI 3.0 specification
- Rate limiting per endpoint

---

## API Structure

```
/api/v1/
├── auth/
│   ├── POST /login
│   ├── POST /refresh
│   └── POST /register
├── publications/
│   ├── GET /{slug}
│   ├── GET /{slug}/posts
│   ├── GET /{slug}/posts/{postSlug}
│   └── POST /{slug}/subscribe
├── posts/ (authenticated authors/editors)
│   ├── POST /
│   ├── PUT /{id}
│   ├── POST /{id}/publish
│   ├── POST /{id}/schedule
│   └── DELETE /{id}
├── subscriptions/ (authenticated users)
│   ├── GET /me
│   ├── POST /cancel
│   └── POST /upgrade
├── media/
│   ├── POST /upload-token
│   └── GET /{id}
└── webhooks/
    ├── POST /stripe
    └── POST /sendgrid
```

---

## Authentication & Authorization

### JWT Authentication

```csharp
namespace Scriber.API.Controllers;

using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Scriber.Application.Auth.Commands;
using Scriber.Application.Common.Messaging;

[ApiController]
[Route("api/v1/auth")]
public class AuthController : ControllerBase
{
    private readonly IMediator _mediator;

    public AuthController(IMediator mediator)
    {
        _mediator = mediator;
    }

    /// <summary>
    /// Authenticate user and return JWT token
    /// </summary>
    [HttpPost("login")]
    [ProducesResponseType(typeof(LoginResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<LoginResponse>> Login(
        [FromBody] LoginRequest request,
        CancellationToken cancellationToken)
    {
        var command = new LoginCommand(request.Email, request.Password);
        var result = await _mediator.Send(command, cancellationToken);

        return Ok(result);
    }

    /// <summary>
    /// Refresh access token using refresh token
    /// </summary>
    [HttpPost("refresh")]
    [ProducesResponseType(typeof(LoginResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<LoginResponse>> Refresh(
        [FromBody] RefreshTokenRequest request,
        CancellationToken cancellationToken)
    {
        var command = new RefreshTokenCommand(request.RefreshToken);
        var result = await _mediator.Send(command, cancellationToken);

        return Ok(result);
    }

    /// <summary>
    /// Register new user account
    /// </summary>
    [HttpPost("register")]
    [ProducesResponseType(typeof(RegisterResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<RegisterResponse>> Register(
        [FromBody] RegisterRequest request,
        CancellationToken cancellationToken)
    {
        var command = new RegisterCommand(request.Email, request.Password, request.DisplayName);
        var result = await _mediator.Send(command, cancellationToken);

        return CreatedAtAction(nameof(Register), new { id = result.UserId }, result);
    }
}

// Request/Response DTOs
public record LoginRequest(string Email, string Password);

public record LoginResponse(
    string AccessToken,
    string RefreshToken,
    DateTime ExpiresAt,
    UserDto User);

public record RefreshTokenRequest(string RefreshToken);

public record RegisterRequest(string Email, string Password, string DisplayName);

public record RegisterResponse(Guid UserId, string Email, string DisplayName);

public record UserDto(Guid Id, string Email, string DisplayName, List<string> Roles);
```

---

## Publications & Posts (Public)

### Publications Controller

```csharp
namespace Scriber.API.Controllers;

using Microsoft.AspNetCore.Mvc;
using Scriber.Application.Publishing.Queries;
using Scriber.Application.Common.Messaging;

[ApiController]
[Route("api/v1/publications")]
public class PublicationsController : ControllerBase
{
    private readonly IMediator _mediator;

    public PublicationsController(IMediator mediator)
    {
        _mediator = mediator;
    }

    /// <summary>
    /// Get publication details by slug
    /// </summary>
    [HttpGet("{slug}")]
    [ProducesResponseType(typeof(PublicationDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<PublicationDto>> GetPublication(
        string slug,
        CancellationToken cancellationToken)
    {
        var query = new GetPublicationQuery(slug);
        var result = await _mediator.Send(query, cancellationToken);

        return Ok(result);
    }

    /// <summary>
    /// Get paginated list of published posts for a publication
    /// </summary>
    [HttpGet("{slug}/posts")]
    [ProducesResponseType(typeof(PaginatedResponse<PostSummaryDto>), StatusCodes.Status200OK)]
    public async Task<ActionResult<PaginatedResponse<PostSummaryDto>>> GetPosts(
        string slug,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? tag = null,
        CancellationToken cancellationToken = default)
    {
        var query = new GetPostListQuery
        {
            PublicationSlug = slug,
            Page = page,
            PageSize = pageSize,
            Tag = tag
        };

        var result = await _mediator.Send(query, cancellationToken);

        return Ok(new PaginatedResponse<PostSummaryDto>
        {
            Items = result.Items,
            TotalCount = result.TotalCount,
            Page = result.Page,
            PageSize = result.PageSize,
            TotalPages = result.TotalPages
        });
    }

    /// <summary>
    /// Get a single post by slug (enforces paywall)
    /// </summary>
    [HttpGet("{publicationSlug}/posts/{postSlug}")]
    [ProducesResponseType(typeof(PostDetailDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<PostDetailDto>> GetPost(
        string publicationSlug,
        string postSlug,
        CancellationToken cancellationToken)
    {
        var query = new GetPostBySlugQuery(publicationSlug, postSlug);
        var result = await _mediator.Send(query, cancellationToken);

        return Ok(result);
    }

    /// <summary>
    /// Subscribe to a publication
    /// </summary>
    [HttpPost("{slug}/subscribe")]
    [ProducesResponseType(typeof(SubscribeResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<SubscribeResponse>> Subscribe(
        string slug,
        [FromBody] SubscribeRequest request,
        CancellationToken cancellationToken)
    {
        // Get publication ID from slug
        var publicationQuery = new GetPublicationQuery(slug);
        var publication = await _mediator.Send(publicationQuery, cancellationToken);

        var command = new SubscribeCommand
        {
            PublicationId = publication.Id,
            Email = request.Email,
            TierId = request.TierId,
            PaymentMethodToken = request.PaymentMethodToken
        };

        var subscriptionId = await _mediator.Send(command, cancellationToken);

        return CreatedAtAction(
            nameof(SubscriptionsController.GetMySubscriptions),
            "Subscriptions",
            null,
            new SubscribeResponse(subscriptionId));
    }
}

// DTOs
public record PublicationDto(
    Guid Id,
    string Name,
    string Slug,
    string? Description,
    List<SubscriptionTierDto> Tiers);

public record SubscriptionTierDto(
    Guid Id,
    string Name,
    decimal Price,
    string Currency,
    string BillingPeriod,
    int TrialDays);

public record SubscribeRequest(
    string Email,
    Guid TierId,
    string? PaymentMethodToken);

public record SubscribeResponse(Guid SubscriptionId);

public record PaginatedResponse<T>
{
    public List<T> Items { get; init; } = new();
    public int TotalCount { get; init; }
    public int Page { get; init; }
    public int PageSize { get; init; }
    public int TotalPages { get; init; }
}
```

---

## Posts Management (Authenticated)

### Posts Controller

```csharp
namespace Scriber.API.Controllers;

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Scriber.Application.Publishing.Commands;
using Scriber.Application.Common.Messaging;

[Authorize]
[ApiController]
[Route("api/v1/posts")]
public class PostsController : ControllerBase
{
    private readonly IMediator _mediator;

    public PostsController(IMediator mediator)
    {
        _mediator = mediator;
    }

    /// <summary>
    /// Create a new draft post
    /// </summary>
    [HttpPost]
    [Authorize(Roles = "Author,Editor")]
    [ProducesResponseType(typeof(CreatePostResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<CreatePostResponse>> CreatePost(
        [FromBody] CreatePostRequest request,
        CancellationToken cancellationToken)
    {
        var command = new CreatePostCommand
        {
            PublicationId = request.PublicationId,
            Title = request.Title,
            Content = request.Content,
            Visibility = request.Visibility,
            Tags = request.Tags
        };

        var postId = await _mediator.Send(command, cancellationToken);

        return CreatedAtAction(
            nameof(PublicationsController.GetPost),
            "Publications",
            new { publicationSlug = "temp", postSlug = "temp" },
            new CreatePostResponse(postId));
    }

    /// <summary>
    /// Update an existing post
    /// </summary>
    [HttpPut("{id:guid}")]
    [Authorize(Roles = "Author,Editor")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<IActionResult> UpdatePost(
        Guid id,
        [FromBody] UpdatePostRequest request,
        CancellationToken cancellationToken)
    {
        var command = new UpdatePostCommand
        {
            PostId = id,
            Title = request.Title,
            Content = request.Content,
            Visibility = request.Visibility,
            Tags = request.Tags
        };

        await _mediator.Send(command, cancellationToken);

        return NoContent();
    }

    /// <summary>
    /// Publish a draft post
    /// </summary>
    [HttpPost("{id:guid}/publish")]
    [Authorize(Roles = "Author,Editor")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<IActionResult> PublishPost(
        Guid id,
        CancellationToken cancellationToken)
    {
        var command = new PublishPostCommand(id);
        await _mediator.Send(command, cancellationToken);

        return NoContent();
    }

    /// <summary>
    /// Schedule a post for future publication
    /// </summary>
    [HttpPost("{id:guid}/schedule")]
    [Authorize(Roles = "Author,Editor")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> SchedulePost(
        Guid id,
        [FromBody] SchedulePostRequest request,
        CancellationToken cancellationToken)
    {
        var command = new SchedulePostCommand(id, request.ScheduledFor);
        await _mediator.Send(command, cancellationToken);

        return NoContent();
    }

    /// <summary>
    /// Delete a post
    /// </summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Roles = "Author,Editor,Admin")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<IActionResult> DeletePost(
        Guid id,
        CancellationToken cancellationToken)
    {
        var command = new DeletePostCommand(id);
        await _mediator.Send(command, cancellationToken);

        return NoContent();
    }
}

// Request DTOs
public record CreatePostRequest(
    Guid PublicationId,
    string Title,
    string Content,
    string Visibility,
    List<string> Tags);

public record CreatePostResponse(Guid PostId);

public record UpdatePostRequest(
    string Title,
    string Content,
    string Visibility,
    List<string> Tags);

public record SchedulePostRequest(DateTime ScheduledFor);
```

---

## Webhooks

### Webhooks Controller

```csharp
namespace Scriber.API.Controllers;

using Microsoft.AspNetCore.Mvc;
using Stripe;
using Scriber.Application.Payments.Commands;
using Scriber.Application.Common.Messaging;

[ApiController]
[Route("api/v1/webhooks")]
public class WebhooksController : ControllerBase
{
    private readonly IMediator _mediator;
    private readonly IConfiguration _configuration;
    private readonly ILogger<WebhooksController> _logger;

    public WebhooksController(
        IMediator mediator,
        IConfiguration configuration,
        ILogger<WebhooksController> logger)
    {
        _mediator = mediator;
        _configuration = configuration;
        _logger = logger;
    }

    /// <summary>
    /// Stripe webhook endpoint for payment events
    /// </summary>
    [HttpPost("stripe")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> StripeWebhook(CancellationToken cancellationToken)
    {
        var json = await new StreamReader(HttpContext.Request.Body).ReadToEndAsync();
        var stripeSignature = Request.Headers["Stripe-Signature"];

        try
        {
            var webhookSecret = _configuration["Stripe:WebhookSecret"];
            var stripeEvent = EventUtility.ConstructEvent(
                json,
                stripeSignature,
                webhookSecret);

            _logger.LogInformation("Received Stripe event: {EventType}", stripeEvent.Type);

            // Handle different event types
            switch (stripeEvent.Type)
            {
                case "invoice.payment_succeeded":
                    var command = new HandleStripePaymentSucceededCommand(
                        stripeEvent.Data.Object as Invoice);
                    await _mediator.Send(command, cancellationToken);
                    break;
            }

            return Ok();
        }
        catch (StripeException ex)
        {
            _logger.LogError(ex, "Stripe webhook signature verification failed");
            return BadRequest();
        }
    }
}
```

---

## Global Error Handling

```csharp
namespace Scriber.API.Filters;

using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Scriber.Application.Common.Exceptions;

public class GlobalExceptionFilter : IExceptionFilter
{
    private readonly ILogger<GlobalExceptionFilter> _logger;

    public GlobalExceptionFilter(ILogger<GlobalExceptionFilter> logger)
    {
        _logger = logger;
    }

    public void OnException(ExceptionContext context)
    {
        var problemDetails = context.Exception switch
        {
            NotFoundException notFound => new ProblemDetails
            {
                Status = StatusCodes.Status404NotFound,
                Title = "Resource Not Found",
                Detail = notFound.Message
            },
            UnauthorizedException => new ProblemDetails
            {
                Status = StatusCodes.Status401Unauthorized,
                Title = "Unauthorized"
            },
            ForbiddenException => new ProblemDetails
            {
                Status = StatusCodes.Status403Forbidden,
                Title = "Forbidden"
            },
            _ => new ProblemDetails
            {
                Status = StatusCodes.Status500InternalServerError,
                Title = "An error occurred"
            }
        };

        _logger.LogError(context.Exception, "Exception occurred");

        context.Result = new ObjectResult(problemDetails)
        {
            StatusCode = problemDetails.Status
        };

        context.ExceptionHandled = true;
    }
}
```

---

## Program.cs Configuration

```csharp
using Scriber.Application;
using Scriber.Infrastructure;
using Scriber.API.Filters;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers(options =>
{
    options.Filters.Add<GlobalExceptionFilter>();
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// JWT Authentication
var jwtSettings = builder.Configuration.GetSection("Jwt");
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtSettings["Issuer"],
            ValidAudience = jwtSettings["Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(jwtSettings["SecretKey"]!))
        };
    });

builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
```

---

## Summary

✅ **RESTful endpoints** - Clean API design  
✅ **JWT authentication** - Secure auth  
✅ **OpenAPI/Swagger** - Auto documentation  
✅ **Error handling** - Consistent responses  
✅ **Webhooks** - Stripe integration  

**Complete design specifications ready for implementation!** 🚀

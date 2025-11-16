# SPEC-2: Domain-Driven Design - Bounded Contexts

## Overview

This document defines the bounded contexts, domain models, and ubiquitous language for the Scriber API, following Domain-Driven Design principles with a frugal innovation mindset.

## Bounded Contexts

### 1. **Publishing Context** (Core Domain)
**Purpose:** Manage content creation, editing, and publication lifecycle.

**Ubiquitous Language:**
- **Post** - A piece of content (article, newsletter)
- **Draft** - Unpublished or work-in-progress content
- **Publication** - A distinct publishing brand/channel
- **Author** - Content creator with publishing rights
- **Editor** - User with content review/approval rights
- **Visibility Tier** - Access level (Public, Free Subscriber, Paid Subscriber)
- **Publish** - Make content available to audience
- **Schedule** - Set future publication time

**Aggregates:**
- **Post Aggregate** (Root: Post)
  - Post (Entity)
  - PostRevision (Value Object)
  - PostTag (Entity)
  - PostMetadata (Value Object)

**Domain Events:**
- `PostDrafted`
- `PostPublished`
- `PostUpdated`
- `PostScheduled`
- `PostUnpublished`

**Key Business Rules:**
- Only authors and editors can create posts
- Published posts cannot transition back to draft (must unpublish first)
- Scheduled posts automatically publish when schedule time reached
- Visibility tier enforces paywall rules

---

### 2. **Subscription Context** (Core Domain)
**Purpose:** Manage subscriber relationships, tiers, and access rights.

**Ubiquitous Language:**
- **Subscriber** - Individual who receives content
- **Subscription** - Active relationship between subscriber and publication
- **Tier** - Level of access (Free, Premium, etc.)
- **Trial Period** - Limited-time free access to paid tier
- **Subscription Status** - Active, PastDue, Canceled, Trialing
- **Renewal** - Automatic subscription continuation

**Aggregates:**
- **Subscription Aggregate** (Root: Subscription)
  - Subscription (Entity)
  - SubscriptionTier (Entity)
  - TrialPeriod (Value Object)
  - BillingCycle (Value Object)

- **Subscriber Aggregate** (Root: Subscriber)
  - Subscriber (Entity)
  - SubscriberPreferences (Value Object)

**Domain Events:**
- `SubscriberRegistered`
- `SubscriptionActivated`
- `SubscriptionRenewed`
- `SubscriptionCanceled`
- `TrialStarted`
- `TrialEnded`
- `SubscriptionDowngraded`
- `SubscriptionUpgraded`

**Key Business Rules:**
- One active subscription per subscriber per publication
- Trial periods cannot be reused by same subscriber
- Canceled subscriptions maintain access until period end
- Past due subscriptions lose access after grace period (7 days)

---

### 3. **Payment Context** (Supporting Domain)
**Purpose:** Handle payment processing, invoicing, and financial transactions.

**Ubiquitous Language:**
- **Payment** - Financial transaction
- **Invoice** - Billing statement
- **Payment Method** - Stored payment instrument
- **Charge** - Debit transaction
- **Refund** - Credit transaction
- **Payment Provider** - External payment processor (Stripe, PayPal)

**Aggregates:**
- **Payment Aggregate** (Root: Payment)
  - Payment (Entity)
  - PaymentMethod (Value Object)
  - Amount (Value Object)
  - Currency (Value Object)

- **Invoice Aggregate** (Root: Invoice)
  - Invoice (Entity)
  - InvoiceLineItem (Entity)
  - InvoiceStatus (Value Object)

**Domain Events:**
- `PaymentInitiated`
- `PaymentSucceeded`
- `PaymentFailed`
- `RefundIssued`
- `InvoiceGenerated`

**Integration Events (from external providers):**
- `StripePaymentSucceeded`
- `StripePaymentFailed`
- `StripeSubscriptionRenewed`

**Key Business Rules:**
- Failed payments trigger retry logic (3 attempts over 7 days)
- Refunds must not exceed original payment amount
- Invoice generated after successful payment
- Payment provider is source of truth for transaction status

---

### 4. **Identity & Access Context** (Generic Subdomain)
**Purpose:** Authentication, authorization, and user management.

**Ubiquitous Language:**
- **User** - Authenticated individual
- **Role** - Permission set (Author, Editor, Admin, Subscriber)
- **Permission** - Specific capability grant
- **Session** - Authenticated user context
- **Credential** - Authentication proof

**Aggregates:**
- **User Aggregate** (Root: User)
  - User (Entity)
  - UserRole (Value Object)
  - Credential (Value Object)

**Domain Events:**
- `UserRegistered`
- `UserRoleChanged`
- `UserAuthenticated`
- `UserDeactivated`

**Key Business Rules:**
- Email must be unique per user
- Password must meet complexity requirements
- Admin role can only be granted by existing admin
- Deactivated users cannot authenticate

---

### 5. **Media Management Context** (Supporting Domain)
**Purpose:** Handle media upload, storage, and delivery.

**Ubiquitous Language:**
- **MediaAsset** - Uploaded file (image, video, document)
- **Upload** - Transfer of file to storage
- **CDN** - Content delivery network
- **Presigned URL** - Time-limited URL for secure upload

**Aggregates:**
- **MediaAsset Aggregate** (Root: MediaAsset)
  - MediaAsset (Entity)
  - AssetMetadata (Value Object)
  - StorageLocation (Value Object)

**Domain Events:**
- `MediaUploaded`
- `MediaDeleted`
- `MediaProcessed` (for image optimization)

**Key Business Rules:**
- Maximum file size: 10MB (images), 50MB (videos)
- Allowed formats: JPEG, PNG, GIF, MP4, PDF
- Media orphaned after 7 days if not linked to post must be deleted

---

### 6. **Notification Context** (Supporting Domain)
**Purpose:** Email delivery, webhook notifications, and event distribution.

**Ubiquitous Language:**
- **Email Campaign** - Batch email to subscriber list
- **Transactional Email** - Single triggered email
- **Webhook** - HTTP callback to external system
- **Email Template** - Reusable message format

**Aggregates:**
- **EmailCampaign Aggregate** (Root: EmailCampaign)
  - EmailCampaign (Entity)
  - EmailRecipient (Entity)
  - DeliveryStatus (Value Object)

- **Webhook Aggregate** (Root: WebhookSubscription)
  - WebhookSubscription (Entity)
  - WebhookDelivery (Entity)

**Domain Events:**
- `EmailQueued`
- `EmailSent`
- `EmailBounced`
- `EmailOpened`
- `EmailClicked`
- `WebhookDelivered`
- `WebhookFailed`

**Key Business Rules:**
- Unsubscribed users excluded from campaigns
- Failed webhook deliveries retry with exponential backoff (max 5 attempts)
- Email rate limited per SendGrid tier

---

## Context Map

```
┌─────────────────────┐
│  Publishing Context │ (Core)
│                     │
└──────┬──────────────┘
       │ publishes
       │ (Conformist)
       ▼
┌─────────────────────┐        ┌──────────────────────┐
│ Subscription Context│◄───────┤ Payment Context      │
│ (Core)              │        │ (Supporting)         │
└──────┬──────────────┘        └──────────────────────┘
       │                                  │
       │ grants access                    │ ACL
       │                                  ▼
       │                        ┌──────────────────────┐
       │                        │ External Payment     │
       │                        │ Provider (Stripe)    │
       │                        └──────────────────────┘
       │
       ▼
┌─────────────────────┐
│ Identity & Access   │
│ (Generic)           │
└─────────────────────┘

┌─────────────────────┐        ┌──────────────────────┐
│ Media Management    │        │ Notification Context │
│ (Supporting)        │        │ (Supporting)         │
└─────────────────────┘        └──────────────────────┘
       ▲                                  ▲
       │                                  │
       │ uses                             │ consumes events
       │                                  │
┌──────┴──────────────┐        ┌──────────┴───────────┐
│  Publishing Context │────────►  Domain Events       │
│                     │ emits  │                      │
└─────────────────────┘        └──────────────────────┘
```

**Relationship Patterns:**
- **Publishing → Subscription**: Conformist (Publishing follows Subscription's access model)
- **Subscription → Payment**: Customer/Supplier (Subscription consumes payment events)
- **Payment → Stripe**: Anti-Corruption Layer (translate external events to domain events)
- **All Contexts → Notification**: Publisher/Subscriber via Domain Events

---

## Frugal Innovation Considerations

### Start Small, Scale Smart
1. **Phase 1 (MVP)**: Single bounded context deployment
   - Deploy Publishing + Subscription + Identity in one API
   - Share database (separate schemas per context)
   - Use simple custom event dispatcher (in-process, zero dependencies)
   - Alternative: Wolverine (free, MIT license) if you need advanced features

2. **Phase 2 (Growth)**: Extract Payment Context
   - Separate microservice when payment volume justifies
   - Azure Service Bus for inter-context events
   - Separate database for payment data compliance
   - Migrate event dispatcher to Azure Service Bus adapter pattern

3. **Phase 3 (Scale)**: Full microservices
   - Split contexts into independent services
   - API Gateway (Kong, Tyk, or cloud-managed) for orchestration

### Cost-Effective Cloud Services
- **Compute**: Container platforms with auto-scaling (Kubernetes, managed container services)
- **Database**: Serverless or managed relational databases (PostgreSQL, MySQL) with auto-pause capabilities
- **Messaging**: Managed message queues or open-source (RabbitMQ, Kafka, NATS)
- **Storage**: Object storage with lifecycle policies (S3-compatible services)
- **Monitoring**: Open-source observability stack (Prometheus, Grafana, Loki) or cloud-native monitoring

### Technical Debt Management
- Keep bounded context boundaries clean from day 1
- Use interfaces for external dependencies (easy to swap providers)
- Domain logic in pure C# classes (no framework dependencies)
- Integration tests for aggregate invariants

### Event Handling & CQRS Strategy (Frugal Approach)

**Phase 1 - Custom MediatR-Like Implementation:**

Instead of paying for MediatR v12+ licensing (~$100/dev/year), we'll implement a custom mediator that provides the same developer experience:

```csharp
// Same familiar interfaces as MediatR
public interface IMediator
{
    Task<TResponse> Send<TResponse>(IRequest<TResponse> request, CancellationToken ct = default);
    Task Publish<TNotification>(TNotification notification, CancellationToken ct = default) 
        where TNotification : INotification;
}

public interface ICommand : IRequest<Unit> { }
public interface ICommand<TResponse> : IRequest<TResponse> { }
public interface IQuery<TResponse> : IRequest<TResponse> { }
public interface INotification { }
```

**What You Get:**
- ✅ **CQRS support** - Commands, queries, and events
- ✅ **Pipeline behaviors** - Validation, logging, transactions, performance monitoring
- ✅ **99% MediatR-compatible** - Same API, easy migration if needed
- ✅ **Zero licensing costs** - Own the code (~350 lines)
- ✅ **Production-ready** - Exception handling, DI, async/await

**Cost Comparison:**
- MediatR v12+: ~$100/dev/year (5 devs × 3 years = **$1,500**)
- Custom implementation: **$0** (4 hours dev time)
- Wolverine (alternative): $0 but steeper learning curve

**3-Year Savings: $1,500+**

**See SPEC-2.2 for complete custom mediator implementation with:**
- Request/response handlers (commands & queries)
- Notification handlers (domain events)
- Pipeline behaviors (validation, logging, transactions)
- Full DI integration
- Usage examples and testing patterns

---

## Next Steps

After this document, you should create:
1. **SPEC-3: Aggregate Design & Domain Models** ✅ - Detailed C# entity designs
2. **SPEC-2.1: Event Dispatcher** (Alternative) - Simple event dispatcher if you don't need CQRS
3. **SPEC-2.2: Custom Mediator** ✅ - MediatR-like implementation (RECOMMENDED)
4. **SPEC-4: Application Services & Use Cases** - CQRS commands/queries using custom mediator
5. **SPEC-5: Infrastructure & Persistence** - Repository patterns, EF Core mappings
6. **SPEC-6: API Contracts** - REST endpoints mapped to use cases
7. **SPEC-7: Deployment Architecture** - Azure resources, Bicep templates

**Recommended Approach:** Use SPEC-2.2 (Custom Mediator) for familiar MediatR patterns without licensing costs.

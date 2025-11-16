# SPEC-1-Substack-like API

## Background

Many writers want an easy, focused platform to publish newsletters, host subscriber-only content, take payments, and manage subscribers — like Substack but tailored to specific needs (e.g., custom branding, different paywall logic, analytics, integrations). This design will produce a RESTful API (MVP) that can serve web and mobile frontends, support free and paid subscriptions, and scale from a single-author blog to multi-author publications.

**Confirmed constraints & assumptions:**
- Product: **RESTful API only** (frontend built by client team).
- Cloud: **Microsoft Azure** (use Azure-managed services where possible).
- Initial scale: small to medium (1–10k MAU), design for easy horizontal scaling.
- Payment and email integrations via webhooks/3rd-party (no built-in payment processor UIs).
- Authentication: token-based (JWT) and OAuth2 support for integrations.

---

## Requirements

### Must (MVP)
- API endpoints for content management: create/read/update/delete (posts, drafts, tags, images). 
- User management: authors, editors, admins; roles & permissions.
- Subscriber management: subscribe/unsubscribe, subscription tiers, trial periods, coupon codes.
- Payments integration: webhooks and subscription lifecycle (charge, cancel, renew) with Stripe and/or PayPal via webhook endpoints.
- Email delivery integration: webhook-based support for transactional and batch emails (SendGrid/Postmark).
- Paywalled content support: post-level visibility flags (public, free-subscriber, paid-subscriber), paywall enforcement in API.
- RESTful pagination, filtering, sorting, and full-text search support for posts (API-level). 
- Audit logs for critical actions (publish, payment events, role changes).
- Rate limiting and basic DDoS protections (Azure API Management + policies).
- HTTPS-only, secure headers, and OWASP best practices.

### Should
- Webhook endpoints to notify frontends and third-party services about events (new post, payment succeeded, subscription canceled).
- Analytics events for opens, clicks, subscription conversions (basic event stream stored and exportable).
- Media (image) upload handling with Azure Blob Storage and automatic CDN (Azure CDN) invalidation.
- Background job processing for email sending, subscription checks, and analytics (Azure Functions / Durable Functions / Azure WebJobs).
- Multi-tenant support (per-publication theming and domain mapping).

### Could
- Native RSS feed generation per publication/tier.
- Content scheduling and queueing with timezone support.
- API-supported WYSIWYG content blocks (structured content) for future extensibility.
- Draft preview tokens for shareable previews.

### Won't (for MVP)
- Built-in rich WYSIWYG editor UI or hosting of frontend.
- In-app payment UI — only server-side API + webhooks.
- Complex multi-currency pricing or localized tax handling (out of scope for MVP; integrate with Stripe Tax later).

---

## Method

### Architecture overview (MVP)

Components (Azure-focused):
- **API Layer:** Containerized REST API (FastAPI/Node.js/ASP.NET Core) deployed to **Azure Container Apps** or **Azure App Service** behind **Azure API Management** (APIM) for authentication, rate-limiting, and routing.
- **Auth & Identity:** **Azure AD B2C** for customer identity (optional) or in-app JWT via Auth server + **Azure Key Vault** for signing keys. Support OAuth2 for integrations.
- **Primary Database:** **Azure Database for PostgreSQL (Flexible Server)** — relational store for users, posts, subscriptions, payments metadata. Use pgcrypto and Postgres full-text search (or integrate with Azure Cognitive Search for advanced search).
- **Cache & Sessions:** **Azure Cache for Redis** — caching public post lists, rate-limiting counters, job dedup keys.
- **Object Storage & CDN:** **Azure Blob Storage** for media assets + **Azure CDN** for distribution.
- **Background Processing & Webhooks:** **Azure Functions** (Durable Functions for orchestrations) + **Azure Service Bus** for event queuing between API and workers.
- **Email & Payments:** Integrate external providers (Stripe webhooks; SendGrid for emails). Expose webhook endpoints to ingest events.
- **Observability:** **Azure Application Insights** (traces, metrics), **Azure Monitor** alerts.
- **Secrets:** **Azure Key Vault** for API keys, DB credentials, webhook secrets.

Deployment & Infra IaC: Use **Bicep** or **Terraform** for reproducible infra.


### High-level data flow
1. Frontend calls API for content/subscription actions.
2. API validates JWT + role, persists changes in Postgres and emits events to Service Bus.
3. Background worker (Azure Function) consumes events for tasks: send email via SendGrid, sync with Stripe, update analytics.
4. Payments provider posts to webhook endpoint; API verifies signature (Key Vault secret) and updates subscription/payment state, emits events.
5. Blob uploads happen via presigned SAS tokens from API; CDN serves media.


### Security & multi-tenant considerations
- Tenancy: add `publication_id` on all tenant-scoped tables; enforce publication scoping in middleware.
- Rate limiting: APIM policies + Redis token buckets for aggressive endpoints.
- Webhook verification: use provider signatures (Stripe `t`+`sig`) validated using Key Vault secret.
- Protect sensitive PII fields at rest & in transit; use field-level encryption if necessary (pgcrypto or application-level).
- Audit logs: append-only `audit_logs` table with `actor_id`, `action`, `resource_type`, `resource_id`, `payload`.


### Database schema (core tables) — implementable SQL

```sql
-- users and roles
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE NOT NULL,
  display_name text,
  password_hash text, -- if not using external IdP
  role text NOT NULL CHECK (role IN ('author','editor','admin','subscriber')),
  created_at timestamptz DEFAULT now(),
  metadata jsonb DEFAULT '{}'
);

-- publications (for multi-tenant)
CREATE TABLE publications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text UNIQUE NOT NULL,
  owner_id uuid REFERENCES users(id),
  settings jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

CREATE TABLE posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid REFERENCES publications(id) NOT NULL,
  author_id uuid REFERENCES users(id) NOT NULL,
  title text NOT NULL,
  slug text NOT NULL,
  status text NOT NULL CHECK (status IN ('draft','published','scheduled')),
  content jsonb NOT NULL, -- store structured content or HTML
  excerpt text,
  visibility text NOT NULL CHECK (visibility IN ('public','free_subscriber','paid_subscriber')),
  canonical_url text,
  published_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX posts_search_idx ON posts USING gin((to_tsvector('english', coalesce(title,'') || ' ' || coalesce((content->>'text'),'') )));

CREATE TABLE tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid REFERENCES publications(id),
  name text NOT NULL,
  slug text NOT NULL
);

CREATE TABLE post_tags (
  post_id uuid REFERENCES posts(id) ON DELETE CASCADE,
  tag_id uuid REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (post_id, tag_id)
);

-- Subscribers and subscriptions
CREATE TABLE subscribers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid REFERENCES publications(id) NOT NULL,
  email text NOT NULL,
  user_id uuid REFERENCES users(id),
  created_at timestamptz DEFAULT now(),
  metadata jsonb DEFAULT '{}'
);

CREATE TABLE subscription_tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid REFERENCES publications(id) NOT NULL,
  name text NOT NULL,
  price_cents integer NOT NULL,
  billing_period text CHECK (billing_period IN ('monthly','yearly')),
  stripe_price_id text
);

CREATE TABLE subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscriber_id uuid REFERENCES subscribers(id) NOT NULL,
  tier_id uuid REFERENCES subscription_tiers(id) NOT NULL,
  status text CHECK (status IN ('active','past_due','canceled','trialing')),
  stripe_subscription_id text,
  current_period_end timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Payments / invoices (metadata)
CREATE TABLE payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid REFERENCES subscriptions(id),
  provider text NOT NULL,
  provider_event jsonb,
  amount_cents integer,
  currency text,
  status text,
  created_at timestamptz DEFAULT now()
);

-- Media
CREATE TABLE media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid REFERENCES publications(id),
  uploader_id uuid REFERENCES users(id),
  blob_url text NOT NULL,
  content_type text,
  width int,
  height int,
  created_at timestamptz DEFAULT now()
);

-- Audit logs
CREATE TABLE audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid REFERENCES users(id),
  action text NOT NULL,
  resource_type text,
  resource_id uuid,
  payload jsonb,
  created_at timestamptz DEFAULT now()
);
```


### API surface (concise, implementable)

Auth:
- POST /auth/login -> { email, password } -> { access_token (JWT), refresh_token }
- POST /auth/refresh -> { refresh_token } -> { access_token }
- POST /auth/oauth/callback -> exchange provider token and return JWT

Public posts:
- GET /publications/{pub}/posts?status=published&tag=tech&page=1&per_page=20
- GET /publications/{pub}/posts/{slug} (returns paywall metadata if not accessible)

Author/editor endpoints (auth required):
- POST /publications/{pub}/posts -> create draft (body: title, content, visibility, tags, scheduled_at)
- PUT /publications/{pub}/posts/{id} -> update
- POST /publications/{pub}/posts/{id}/publish -> publishes (creates audit log)
- DELETE /publications/{pub}/posts/{id}

Subscriptions & payments:
- POST /publications/{pub}/subscribe -> { email, tier_id, payment_method_token } -> returns subscription object (or redirect URL for hosted checkout)
- POST /webhooks/payments/stripe -> receives Stripe events, verifies signature, updates subscriptions/payments
- GET /publications/{pub}/subscribers/{id} (auth limited)

Media:
- POST /publications/{pub}/media/sas -> returns SAS upload token + target path
- GET /publications/{pub}/media/{id}

Webhooks & events:
- POST /webhooks/sendgrid (email events)
- POST /webhooks/custom -> generic event ingestion for 3rd party

Admin:
- GET /admin/publications, POST /admin/publications, PUT /admin/publications/{id}
- GET /admin/audit-logs?limit=100


### Background jobs & algorithms
- **Subscription reconciliation worker:** consumes Stripe events; idempotency keys stored in Redis to avoid double-processing. On event: map stripe_subscription_id -> subscriptions row, update status, emit notification event.
- **Paywall enforcement:** API reads `visibility` + subscription status; algorithm: if post.visibility == 'public' -> serve full; if 'free_subscriber' -> check subscribers table for active subscription (free or paid); if 'paid_subscriber' -> require active paid subscription tier.
- **Search:** lightweight using Postgres tsvector indexed on title + content; for larger scale, sync to Azure Cognitive Search via Service Bus.
- **Email send batching:** group sends by publication and template; use durable function to send in batches with exponential backoff on transient failures.


## Implementation

### Tech stack recommendations (MVP)
- Language: **TypeScript (Node + Fastify)** or **Python (FastAPI)** — both have great async ecosystems and are container-friendly.
- ORM: **Prisma** (TypeScript) or **SQLAlchemy + Alembic** (Python) for migrations and schema management.
- Background: **Azure Functions** (Python/Node) or a container worker pool on Azure Container Instances/Apps.
- Infra as Code: **Bicep** for Azure resources or **Terraform** if you prefer multi-cloud.
- CI/CD: GitHub Actions -> build container -> push to ACR -> deploy to Azure Container Apps.
- Observability: Application Insights + structured logging (JSON) + distributed tracing.


### Implementation steps (high level)
1. Scaffold API project + authentication module + Postgres schema migrations.
2. Implement core models: publications, users, posts, subscribers, tiers, subscriptions.
3. Add Stripe webhook handler + local emulator tests; add SAS media upload endpoints.
4. Implement paywall logic and protected content endpoints.
5. Add background workers for email & subscription reconciliation; wire Service Bus.
6. Add APIM configuration, rate limiting policies.
7. Add telemetry, monitoring, and alerting.
8. Load test basic flows (post publishing, subscribe, webhook ingestion) and optimize indexes & caching.


## Milestones
1. Week 0–2: Project scaffolding, infra IaC (Postgres, Redis, Blob), auth, core DB models.
2. Week 3–4: Posts API, media upload flow, paywall enforcement, basic public endpoints.
3. Week 5–6: Stripe integration + webhook handling + subscription lifecycle.
4. Week 7–8: Background workers, email integration (SendGrid), webhooks for events.
5. Week 9–10: APIM, rate-limiting, monitoring, and hardening; staging deployment and smoke tests.


## Gathering Results
- Key success metrics: time-to-first-publish, subscription conversion rate, webhook processing latency, error rates in Application Insights.
- Post-launch: run a 72-hour soak test with synthetic traffic replicating expected patterns; use results to tune DB indices, Redis TTLs, and function concurrency.


## PlantUML Architecture Diagram

```plantuml
@startuml
!define AWSPUML https://raw.githubusercontent.com/awslabs/aws-icons-for-plantuml/v14.0/Advanced/AWSPUML
actor "Frontend App" as F
node "APIM" as APIM
node "Container Apps / App Service (API)" as API
queue "Service Bus" as SB
node "Azure Functions / Workers" as WF
database "Postgres (Azure DB)" as PG
queue "Redis Cache" as REDIS
storage "Blob Storage + CDN" as BLOB
cloud "Stripe / SendGrid" as EX
F --> APIM --> API
API --> PG
API --> REDIS
API --> SB
API --> BLOB
SB --> WF
WF --> EX
WF --> PG
APIM --> EX : webhooks
@enduml
```


---

If you want, I can now:
- produce a full OpenAPI (Swagger) spec for the API surface above, or
- export the SQL schema as runnable migration files, or
- provide a sample FastAPI or Express project scaffold with authentication and a posts CRUD implemented.

Which of those would you like me to deliver next? (pick one)


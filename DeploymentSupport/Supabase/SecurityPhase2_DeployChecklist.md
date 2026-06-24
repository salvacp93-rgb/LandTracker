# Security Phase 2 - Deploy Checklist

Use this after finishing the changes in:
- `SupabaseUserManagementSetup.sql`
- `SupabaseSecurityPhase2.sql`
- `SupabaseTaskPushWorker.ts`

## 1) Execute SQL phase 2

In Supabase SQL Editor, run:
- `SupabaseSecurityPhase2.sql`

What this enables:
- Per-user/per-table write throttling triggers.
- Security telemetry table (`security_events`).
- Distributed worker lock (`worker_job_locks`) for internal jobs.
- Payload length constraints (NOT VALID, enforced for new writes).

## 2) Deploy edge worker with auth token

Move worker file to your Supabase function folder:
- `supabase/functions/task-push-worker/index.ts`

Set function secrets:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `APNS_TEAM_ID`
- `APNS_KEY_ID`
- `APNS_PRIVATE_KEY`
- `APNS_BUNDLE_ID`
- `TASK_PUSH_WORKER_TOKEN` (new secret for caller auth)
- Optional:
  - `TASK_PUSH_MAX_LIMIT_COUNT` (default `200`)
  - `TASK_PUSH_DEFAULT_LIMIT_COUNT` (default `100`)
  - `TASK_PUSH_LOCK_SECONDS` (default `120`)

Deploy:
- `supabase functions deploy task-push-worker`

## 3) Invoke only with bearer token

When scheduler/automation calls the worker, send:
- `Authorization: Bearer <TASK_PUSH_WORKER_TOKEN>`
- `Content-Type: application/json`

Optional body:
```json
{ "limitCount": 100 }
```

## 4) Add scheduled cleanup

Run periodically (daily) using service_role:
- `select public.cleanup_security_telemetry(45);`

## 5) Validate protections

Check these cases:
- Calling worker without token returns `401`.
- Rapid repeated calls return `429` (rate limit) and/or `409` (already running lock).
- Aggressive writes from one user eventually return `rate_limit_exceeded`.
- Events are stored in `public.security_events`.

## 6) Optional edge/WAF hardening

If you put a gateway in front (Cloudflare or similar), add:
- Rate limit rule for function route.
- Bot challenge for suspicious traffic.
- Geo/IP firewall rules if you have known traffic regions.


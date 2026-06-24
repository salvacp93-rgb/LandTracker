// Supabase Edge Function template for APNs task reminders.
// Suggested path after moving:
// supabase/functions/task-push-worker/index.ts

import { createClient } from "npm:@supabase/supabase-js@2.50.0";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";

type PendingPushRow = {
  task_id: string;
  user_id: string;
  device_token: string;
  task_title: string;
  land_name: string;
  due_date: string;
  reminder_date: string;
};

type AuthContext = {
  authorized: boolean;
  identifier: string;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const apnsTeamID = Deno.env.get("APNS_TEAM_ID") ?? "";
const apnsKeyID = Deno.env.get("APNS_KEY_ID") ?? "";
const apnsPrivateKey = (Deno.env.get("APNS_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
const apnsTopic = Deno.env.get("APNS_BUNDLE_ID") ?? "";
const apnsHost = Deno.env.get("APNS_HOST") ?? "api.push.apple.com";

// Internal shared secret to invoke this function (use with scheduler/automation only).
const workerInvokeToken = Deno.env.get("TASK_PUSH_WORKER_TOKEN") ?? "";

const maxLimitCount = Number.parseInt(Deno.env.get("TASK_PUSH_MAX_LIMIT_COUNT") ?? "200", 10);
const defaultLimitCount = Number.parseInt(Deno.env.get("TASK_PUSH_DEFAULT_LIMIT_COUNT") ?? "100", 10);
const lockSeconds = Number.parseInt(Deno.env.get("TASK_PUSH_LOCK_SECONDS") ?? "120", 10);

const required = [
  ["SUPABASE_URL", supabaseUrl],
  ["SUPABASE_SERVICE_ROLE_KEY", supabaseServiceRoleKey],
  ["APNS_TEAM_ID", apnsTeamID],
  ["APNS_KEY_ID", apnsKeyID],
  ["APNS_PRIVATE_KEY", apnsPrivateKey],
  ["APNS_BUNDLE_ID", apnsTopic],
  ["TASK_PUSH_WORKER_TOKEN", workerInvokeToken]
];

for (const [name, value] of required) {
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
}

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: { persistSession: false }
});

function toBoundedInteger(rawValue: number, fallback: number, minValue: number, maxValue: number): number {
  if (!Number.isFinite(rawValue)) {
    return fallback;
  }
  return Math.min(Math.max(Math.floor(rawValue), minValue), maxValue);
}

function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const left = encoder.encode(a);
  const right = encoder.encode(b);

  let mismatch = left.length ^ right.length;
  const maxLength = Math.max(left.length, right.length);
  for (let i = 0; i < maxLength; i += 1) {
    const l = i < left.length ? left[i] : 0;
    const r = i < right.length ? right[i] : 0;
    mismatch |= l ^ r;
  }
  return mismatch === 0;
}

function callerIdentifier(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for") ?? "";
  const firstIp = forwarded.split(",")[0]?.trim();
  if (firstIp) {
    return `ip:${firstIp}`;
  }

  const realIp = req.headers.get("x-real-ip")?.trim();
  if (realIp) {
    return `ip:${realIp}`;
  }

  return "ip:unknown";
}

function extractBearerToken(req: Request): string {
  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return "";
  }
  return authHeader.slice(7).trim();
}

function authContextFromRequest(req: Request): AuthContext {
  const token = extractBearerToken(req);
  return {
    authorized: token.length > 0 && timingSafeEqual(token, workerInvokeToken),
    identifier: callerIdentifier(req)
  };
}

async function enforceInvocationRateLimit(identifier: string): Promise<void> {
  const burst = await supabase.rpc("enforce_rate_limit", {
    p_scope: "task_push_worker_invocation_burst",
    p_identifier: identifier,
    p_max_hits: 6,
    p_window_seconds: 60
  });
  if (burst.error) {
    throw burst.error;
  }

  const hourly = await supabase.rpc("enforce_rate_limit", {
    p_scope: "task_push_worker_invocation_hourly",
    p_identifier: identifier,
    p_max_hits: 120,
    p_window_seconds: 3600
  });
  if (hourly.error) {
    throw hourly.error;
  }
}

async function acquireWorkerLock(): Promise<string | null> {
  const lockForSeconds = toBoundedInteger(lockSeconds, 120, 30, 600);
  const { data, error } = await supabase.rpc("acquire_worker_job_lock", {
    p_job_name: "task_push_worker",
    p_lock_seconds: lockForSeconds
  });
  if (error) {
    throw error;
  }
  if (typeof data !== "string" || data.trim().length === 0) {
    return null;
  }
  return data.trim();
}

async function releaseWorkerLock(lockToken: string): Promise<void> {
  if (!lockToken) {
    return;
  }
  const { error } = await supabase.rpc("release_worker_job_lock", {
    p_job_name: "task_push_worker",
    p_lock_token: lockToken
  });
  if (error) {
    console.error("Failed to release task_push_worker lock", error);
  }
}

async function limitCountFromRequest(req: Request): Promise<number> {
  const safeMax = toBoundedInteger(maxLimitCount, 200, 1, 500);
  const safeDefault = toBoundedInteger(defaultLimitCount, 100, 1, safeMax);

  if (req.method !== "POST") {
    return safeDefault;
  }

  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    return safeDefault;
  }

  try {
    const body = (await req.json()) as { limitCount?: number };
    const maybeLimit = body?.limitCount;
    if (typeof maybeLimit !== "number") {
      return safeDefault;
    }
    return toBoundedInteger(maybeLimit, safeDefault, 1, safeMax);
  } catch {
    return safeDefault;
  }
}

async function createAPNsJWT(): Promise<string> {
  const privateKey = await importPKCS8(apnsPrivateKey, "ES256");
  const now = Math.floor(Date.now() / 1000);
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: apnsKeyID })
    .setIssuer(apnsTeamID)
    .setIssuedAt(now)
    .sign(privateKey);
}

async function sendAPNSNotification(
  deviceToken: string,
  bearerToken: string,
  title: string,
  body: string
): Promise<{ ok: boolean; status: number; reason?: string }> {
  const payload = {
    aps: {
      alert: { title, body },
      sound: "default"
    }
  };

  const response = await fetch(`https://${apnsHost}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${bearerToken}`,
      "apns-topic": apnsTopic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json"
    },
    body: JSON.stringify(payload)
  });

  if (response.ok) {
    return { ok: true, status: response.status };
  }

  let reason: string | undefined;
  try {
    const json = await response.json();
    reason = typeof json?.reason === "string" ? json.reason : undefined;
  } catch {
    reason = undefined;
  }

  return { ok: false, status: response.status, reason };
}

function dueText(dateISO: string): string {
  const date = new Date(dateISO);
  return date.toISOString().replace("T", " ").slice(0, 16) + " UTC";
}

async function markDelivered(row: PendingPushRow): Promise<void> {
  const { error } = await supabase.from("land_task_push_deliveries").insert({
    task_id: row.task_id,
    user_id: row.user_id,
    device_token: row.device_token,
    reminder_date: row.reminder_date
  });

  // Unique collisions can happen if two workers overlap.
  if (error && error.code !== "23505") {
    console.error("Failed to mark delivery", error);
  }
}

async function removeInvalidDeviceToken(row: PendingPushRow): Promise<void> {
  const { error } = await supabase
    .from("push_devices")
    .delete()
    .eq("user_id", row.user_id)
    .eq("device_token", row.device_token);

  if (error) {
    console.error("Failed to delete invalid token", error);
  }
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store"
    }
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  const authCtx = authContextFromRequest(req);
  if (!authCtx.authorized) {
    return jsonResponse({ ok: false, error: "unauthorized" }, 401);
  }

  try {
    await enforceInvocationRateLimit(authCtx.identifier);
  } catch (error) {
    const normalized = `${error}`.toLowerCase();
    if (normalized.includes("rate_limit_exceeded")) {
      return jsonResponse({ ok: false, error: "rate_limit_exceeded" }, 429);
    }
    console.error("Failed invocation rate limit check", error);
    return jsonResponse({ ok: false, error: "rate_limit_check_failed" }, 500);
  }

  let lockToken: string | null = null;
  try {
    lockToken = await acquireWorkerLock();
    if (!lockToken) {
      return jsonResponse({ ok: false, error: "worker_already_running" }, 409);
    }

    const requestedLimit = await limitCountFromRequest(req);
    const { data, error } = await supabase.rpc("pending_land_task_push_notifications", {
      limit_count: requestedLimit
    });

    if (error) {
      return jsonResponse({ ok: false, stage: "query", error: error.message }, 500);
    }

    const rows = (data ?? []) as PendingPushRow[];
    if (rows.length === 0) {
      return jsonResponse({ ok: true, processed: 0, sent: 0, failed: 0, removed: 0 }, 200);
    }

    const bearerToken = await createAPNsJWT();

    let sent = 0;
    let failed = 0;
    let removed = 0;

    for (const row of rows) {
      const body = `${row.land_name} - Due ${dueText(row.due_date)}`;
      const result = await sendAPNSNotification(row.device_token, bearerToken, row.task_title, body);

      if (result.ok) {
        sent += 1;
        await markDelivered(row);
        continue;
      }

      failed += 1;
      const badTokenReasons = new Set(["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"]);
      if (result.status === 410 || (result.reason && badTokenReasons.has(result.reason))) {
        removed += 1;
        await removeInvalidDeviceToken(row);
      }
    }

    return jsonResponse(
      {
        ok: true,
        processed: rows.length,
        sent,
        failed,
        removed
      },
      200
    );
  } finally {
    if (lockToken) {
      await releaseWorkerLock(lockToken);
    }
  }
});

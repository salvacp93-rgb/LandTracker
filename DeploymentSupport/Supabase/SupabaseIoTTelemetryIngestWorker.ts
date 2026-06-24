// Supabase Edge Function template for IoT telemetry ingestion.
// Suggested path after moving:
// supabase/functions/iot-telemetry-ingest/index.ts

import { createClient } from "npm:@supabase/supabase-js@2.50.0";

type IngestPayload = {
  device_id?: string;
  observed_at?: string;
  metric_name?: string | null;
  metric_unit?: string | null;
  value_double?: number | null;
  value_text?: string | null;
  battery_level?: number | null;
  status_raw?: string | null;
  source_raw?: string | null;
  payload?: Record<string, string> | null;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const iotIngestToken = Deno.env.get("IOT_INGEST_TOKEN") ?? "";
const ingressRateLimitPerMinute = Number.parseInt(
  Deno.env.get("IOT_INGEST_RATE_PER_MINUTE") ?? "120",
  10
);

const required = [
  ["SUPABASE_URL", supabaseUrl],
  ["SUPABASE_SERVICE_ROLE_KEY", supabaseServiceRoleKey],
  ["IOT_INGEST_TOKEN", iotIngestToken]
];

for (const [name, value] of required) {
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
}

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: { persistSession: false }
});

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

function extractBearerToken(req: Request): string {
  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return "";
  }
  return authHeader.slice(7).trim();
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

function normalizePayloadBody(raw: unknown): IngestPayload {
  if (!raw || typeof raw !== "object") {
    return {};
  }
  const payload = raw as IngestPayload;
  return payload;
}

function normalizedPayloadText(payload?: Record<string, string> | null): string {
  if (!payload || typeof payload !== "object") {
    return "{}";
  }
  const safeEntries = Object.entries(payload).filter(
    ([key, value]) => typeof key === "string" && typeof value === "string"
  );
  if (safeEntries.length === 0) {
    return "{}";
  }
  return JSON.stringify(Object.fromEntries(safeEntries));
}

function asNullableString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function asNullableNumber(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  return value;
}

async function enforceIngressRateLimit(identifier: string): Promise<void> {
  const maxHits = Number.isFinite(ingressRateLimitPerMinute)
    ? Math.min(Math.max(Math.floor(ingressRateLimitPerMinute), 30), 10000)
    : 120;

  const { error } = await supabase.rpc("enforce_rate_limit", {
    p_scope: "iot_ingest_http_burst",
    p_identifier: identifier,
    p_max_hits: maxHits,
    p_window_seconds: 60
  });
  if (error) {
    throw error;
  }
}

function response(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" }
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return response(405, { error: "method_not_allowed" });
  }

  const bearer = extractBearerToken(req);
  if (!bearer || !timingSafeEqual(bearer, iotIngestToken)) {
    return response(401, { error: "unauthorized" });
  }

  try {
    await enforceIngressRateLimit(callerIdentifier(req));
  } catch (error) {
    console.error("Rate limit enforcement failed", error);
    return response(429, { error: "rate_limited" });
  }

  let payload: IngestPayload;
  try {
    payload = normalizePayloadBody(await req.json());
  } catch {
    return response(400, { error: "invalid_json" });
  }

  const deviceID = asNullableString(payload.device_id);
  if (!deviceID) {
    return response(400, { error: "missing_device_id" });
  }

  const observedAt = asNullableString(payload.observed_at) ?? new Date().toISOString();
  const metricName = asNullableString(payload.metric_name);
  const metricUnit = asNullableString(payload.metric_unit);
  const valueDouble = asNullableNumber(payload.value_double);
  const valueText = asNullableString(payload.value_text);
  const batteryLevel = asNullableNumber(payload.battery_level);
  const statusRaw = asNullableString(payload.status_raw);
  const sourceRaw = asNullableString(payload.source_raw) ?? "device_push";
  const payloadText = normalizedPayloadText(payload.payload);

  try {
    const { data, error } = await supabase.rpc("append_iot_telemetry", {
      p_device_id: deviceID,
      p_observed_at: observedAt,
      p_metric_name: metricName,
      p_metric_unit: metricUnit,
      p_value_double: valueDouble,
      p_value_text: valueText,
      p_battery_level: batteryLevel,
      p_status_raw: statusRaw,
      p_source_raw: sourceRaw,
      p_payload_text: payloadText
    });

    if (error) {
      console.error("append_iot_telemetry failed", error);
      return response(400, { error: "append_failed", detail: error.message });
    }

    return response(200, {
      ok: true,
      telemetry_id: data,
      observed_at: observedAt
    });
  } catch (error) {
    console.error("Unexpected ingest error", error);
    return response(500, { error: "internal_error" });
  }
});

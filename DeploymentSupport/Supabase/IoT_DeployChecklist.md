# IoT Phase 1 - Deploy Checklist

Use this after:
- `SupabaseCloudSetup.sql`
- `SupabaseUserManagementSetup.sql`

## 1) Run IoT SQL

In Supabase SQL Editor, run:
- `SupabaseIoTSetup.sql`

What this enables:
- Device registry: `public.iot_devices`
- Telemetry stream: `public.iot_device_telemetry`
- Command queue: `public.iot_device_commands`
- Org-aware RLS policies and helper RPC functions.

## 2) Verify from SQL editor

As an authenticated user with organization membership:
- Register a device:
  - `select public.register_iot_device('<land_uuid>'::uuid, null, 'Sensor demo');`
- Append telemetry:
  - `select public.append_iot_telemetry('<device_uuid>'::uuid, now(), 'temperature', 'C', 24.6);`
- Enqueue command:
  - `select public.enqueue_iot_device_command('<device_uuid>'::uuid, 'ping', '{"priority":"normal"}');`

## 3) Verify in app

- Add a device in a land detail view.
- Confirm rows appear in `public.iot_devices`.
- If device has initial metric/battery data, confirm row appears in `public.iot_device_telemetry`.

## 4) Next step (real-time transport)

For true real-time from physical devices, add an ingestion service (MQTT/Webhook) that writes telemetry with `service_role`:
- Preferred stack: MQTT broker -> ingestion worker -> `append_iot_telemetry`.
- Edge template included in this repo: `SupabaseIoTTelemetryIngestWorker.ts`.
- Keep command delivery through `iot_device_commands` polling or worker push.

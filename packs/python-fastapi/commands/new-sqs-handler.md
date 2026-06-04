# New Queue Event Handler (inbound consumer)

> **EXAMPLE — python/FastAPI stack pack command.** Activated when `/install` detects
> python. Adapt or replace for your stack. The asyncio queue-consumer pattern below is an
> illustrative convention for inbound cross-service events — keep what fits your project,
> drop what doesn't.

Add a background consumer for an inbound cross-service event: $ARGUMENTS

`$ARGUMENTS` = the event type to consume, e.g. `lis.order.confirmed`.

This stack consumes cross-service events via an **asyncio queue consumer Task started in
the FastAPI lifespan**. Model it on an existing service's consumer worker
(`app/workers/<name>_consumer.py`).

## The consumer contract (per-message processing)

```python
# app/workers/<name>_consumer.py
1. Parse the platform envelope (handle any pub/sub -> queue fan-out wrapping).
2. Filter to event_type == "$ARGUMENTS" — ignore others.
3. Dedup by event_id via Redis (24h TTL key: seen_event:<service>:{event_id}).
   - The queue is AT-LEAST-ONCE; without dedup you double-process.
4. Re-derive identity / tenant from the payload — NEVER trust ambient state.
5. Do the business work + audit row in ONE DB transaction (atomic).
6. ACK (delete the message) on success OR on an idempotent no-op.
```

## Failure policy (DLQ-friendly) — do NOT delete on retryable failures

```python
- Transient (downstream service unavailable) -> do NOT delete -> visibility-timeout retry.
- Configuration error (e.g. item not priced) -> do NOT delete -> eventually lands in DLQ
  for ops; processes correctly once configured. Never write a half-valid record.
- Any other exception -> do NOT delete -> retry -> DLQ.
- Only delete (ACK) on genuine success or a proven idempotent no-op.
```

## Wiring

```python
# main.py lifespan — start the consumer Task (gated by a setting so tests don't hit the queue SDK)
if settings.CONSUMERS_ENABLED:
    app.state.<name>_consumer = asyncio.create_task(run_<name>_consumer())
# ... and cancel it on shutdown.
```

- `CONSUMERS_ENABLED` (default True) → set False in tests to avoid real queue-client creation.
- Inbound queue URL comes from `settings` (env), never hardcoded.
- Tenant isolation still applies: re-derive `tenant_id` from the payload and scope all writes.

## Quality Verification Checklist

- [ ] **Envelope parsing** handles any pub/sub→queue wrapping
- [ ] **event_type filter** — only `$ARGUMENTS` is processed
- [ ] **Redis dedup** by `event_id` (at-least-once safe), with TTL
- [ ] **Identity/tenant re-derived** from payload (no ambient trust); writes are tenant-scoped
- [ ] **Atomic** business write + audit row in one transaction
- [ ] **ACK only on success / idempotent no-op**; retryable failures are NOT deleted (DLQ path)
- [ ] **CONSUMERS_ENABLED** gate so tests don't instantiate the queue client
- [ ] **Queue URL from settings** (env)
- [ ] **TimeManager** for timestamps; **structured logger** (no print)
- [ ] **CONTEXT.md + the producer's contract** referenced (freshness rule)
- [ ] **Tests**: happy path, dedup (redelivery → no double-process), retryable failure → no ACK
- [ ] **FULL-tier** change (cross-service contract) — full critic→fixer→auditor

## Notes

- Bind to the producer's payload contract EXACTLY (required vs optional fields). If a
  required field (e.g. `channel` for price resolution) is absent, REJECT the message
  (retry/DLQ) — never guess.
- The matching emit side is `/new-event`. Producer and consumer both own the contract.

# New Outbound Event (transactional outbox)

> **EXAMPLE — python/FastAPI stack pack command.** Activated when `/install` detects
> python. Adapt or replace for your stack. The transactional-outbox pattern below is an
> illustrative convention for reliable cross-service events — keep what fits your project,
> drop what doesn't.

Emit a new domain event reliably via the transactional outbox: $ARGUMENTS

`$ARGUMENTS` = the dot-separated event type, e.g. `accounting.invoice.finalised`.

This stack emits cross-service events through a **transactional outbox**, NOT a direct
queue call. The outbox row is written in the SAME DB transaction as the business change; a
background publisher drains it to the message queue with backoff. This guarantees the event
is emitted iff the business write committed (no lost or phantom events). Model it on an
existing service that already has an `outbox` table + an `outbox_publisher` worker.

## Steps

### 1. Define the event envelope payload
Use the platform event envelope (a shared `event_envelope` helper, if your project has one).
The payload must carry at least: `event_id` (UUID, for consumer dedup), `event_type`,
`tenant_id`, `occurred_at`, and the domain fields consumers bind to.

### 2. Write the outbox row INSIDE the business transaction

```python
# In the service method that makes the business change — SAME db_session, SAME transaction
from app.models.outbox import Outbox
from app.core.utils.time import time_manager

outbox_row = Outbox(
    event_type="$ARGUMENTS",
    event_payload=envelope,                 # the full platform envelope (JSONB)
    target_queue_url=settings.OUTBOX_TARGET_QUEUE_URL,
    tenant_id=tenant_id,
    request_id=request_id,                  # for trace correlation
)
db_session.add(outbox_row)
# ... the business write is on the SAME db_session ...
await db_session.commit()                   # both land atomically, or neither does
```

### 3. Let the publisher drain it
The background `outbox_publisher` loop (started in lifespan) polls `status='pending'` rows,
sends to the queue, and flips `pending -> sent` (or `-> failed` after `OUTBOX_MAX_ATTEMPTS`
with exponential backoff via `next_attempt_at`). You do NOT call the queue SDK directly from
the request path.

### 4. Document the contract (cross-service)
This event is a CROSS-SERVICE CONTRACT. In the SAME PR:
- Add the event shape to the service's `docs/events.json` and `CONTEXT.md`.
- List it under "Cross-service impact" in the PR description.
- If a consumer exists, update the consumer's design doc too (both sides own the contract).

## Quality Verification Checklist

- [ ] **Outbox row written in the SAME transaction** as the business change (atomic)
- [ ] **Envelope carries `event_id`** (consumer dedup) + `tenant_id` + `occurred_at`
- [ ] **No direct queue SDK send** from the request path — publisher drains the outbox
- [ ] **target_queue_url from settings** (env), never hardcoded
- [ ] **TimeManager** for any timestamps
- [ ] **events.json + CONTEXT.md updated** (freshness rule); PR "Cross-service impact" lists it
- [ ] **Tests**: outbox row created on commit; NOT created if the business txn rolls back
- [ ] **This is a FULL-tier change** (cross-service contract) — full critic→fixer→auditor

## Notes

- Reuse the existing `Outbox` model + publisher if the service already has them; only add
  the migration for `outbox` if this is the service's first event.
- If the service has no outbox yet, model it on an existing service's (`outbox` table,
  status lifecycle `pending -> sent -> failed`, backoff columns).

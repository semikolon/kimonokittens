-- Audit log for SMS events (sent, received, delivery receipts)
CREATE TABLE "SmsEvent" (
  "id" TEXT NOT NULL,
  "tenantId" TEXT,  -- Null for admin SMS
  "month" TEXT,  -- "2025-11" (for rent reminders)
  "direction" TEXT NOT NULL,  -- "out" | "in" | "dlr"
  "providerId" TEXT,  -- 46elks message ID (for idempotency)
  "body" TEXT NOT NULL,  -- SMS text content
  "parts" INTEGER,  -- Number of SMS parts (160 chars each)
  "status" TEXT,  -- "sent" | "delivered" | "failed"
  "meta" JSONB,  -- Extra: delivery timestamps, error codes, tone
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "SmsEvent_pkey" PRIMARY KEY ("id")
);

-- Foreign key to Tenant (nullable for admin SMS)
CREATE INDEX "SmsEvent_tenantId_idx" ON "SmsEvent"("tenantId");
ALTER TABLE "SmsEvent" ADD CONSTRAINT "SmsEvent_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Query optimization indices
CREATE INDEX "SmsEvent_tenantId_month_idx" ON "SmsEvent"("tenantId", "month");
CREATE INDEX "SmsEvent_direction_createdAt_idx" ON "SmsEvent"("direction", "createdAt" DESC);
CREATE INDEX "SmsEvent_providerId_idx" ON "SmsEvent"("providerId");

-- Comments
COMMENT ON TABLE "SmsEvent" IS 'Audit log for all SMS events - sent, received, delivery receipts';
COMMENT ON COLUMN "SmsEvent"."direction" IS 'Message direction: out (sent to tenant/admin), in (received from tenant), dlr (delivery receipt)';
COMMENT ON COLUMN "SmsEvent"."providerId" IS '46elks message ID - used for idempotency and delivery receipt matching';
COMMENT ON COLUMN "SmsEvent"."parts" IS 'Number of SMS parts (160 chars each) for cost tracking';
COMMENT ON COLUMN "SmsEvent"."meta" IS 'Extra data: delivery timestamps, error codes, reminder tone, from/to numbers';

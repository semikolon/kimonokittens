-- Store bank transactions from Lunch Flow API for rent payment reconciliation
CREATE TABLE "BankTransaction" (
  "id" TEXT NOT NULL,
  "externalId" TEXT NOT NULL,  -- Lunch Flow transaction ID (deduplication)
  "accountId" TEXT NOT NULL,   -- Lunch Flow account ID
  "bookedAt" TIMESTAMP(3) NOT NULL,  -- When transaction posted to bank
  "amount" DECIMAL(12,2) NOT NULL,
  "currency" TEXT NOT NULL DEFAULT 'SEK',
  "description" TEXT NOT NULL,  -- "SWISH SANNA BENEMAR KK-2025-11-Sanna-cmhqe9enc"
  "counterparty" TEXT,  -- "Sanna Benemar"
  "rawJson" JSONB NOT NULL,  -- Full Lunch Flow API response
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "BankTransaction_pkey" PRIMARY KEY ("id")
);

-- Unique constraint: prevent duplicate transactions
CREATE UNIQUE INDEX "BankTransaction_externalId_key" ON "BankTransaction"("externalId");

-- Query optimization indices
CREATE INDEX "BankTransaction_bookedAt_idx" ON "BankTransaction"("bookedAt" DESC);
CREATE INDEX "BankTransaction_accountId_bookedAt_idx" ON "BankTransaction"("accountId", "bookedAt" DESC);

-- Comments
COMMENT ON TABLE "BankTransaction" IS 'Bank transactions from Lunch Flow hourly sync for rent payment reconciliation';
COMMENT ON COLUMN "BankTransaction"."externalId" IS 'Lunch Flow transaction ID - used for deduplication in hourly sync';
COMMENT ON COLUMN "BankTransaction"."counterparty" IS 'Payer name for fuzzy matching in payment reconciliation';
COMMENT ON COLUMN "BankTransaction"."rawJson" IS 'Full Lunch Flow API response for debugging and future fields';

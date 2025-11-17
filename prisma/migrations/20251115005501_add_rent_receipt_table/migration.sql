-- Link bank transactions to tenant rent payments (double-entry ledger)
CREATE TABLE "RentReceipt" (
  "id" TEXT NOT NULL,
  "month" TEXT NOT NULL,  -- "2025-11" (period this payment applies to)
  "tenantId" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL,
  "matchedTxId" TEXT,  -- FK to BankTransaction (null = manual entry)
  "matchedVia" TEXT NOT NULL,  -- "reference" | "amount+name" | "manual"
  "paidAt" TIMESTAMP(3) NOT NULL,  -- When payment was received
  "partial" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "RentReceipt_pkey" PRIMARY KEY ("id")
);

-- Foreign keys
CREATE INDEX "RentReceipt_tenantId_idx" ON "RentReceipt"("tenantId");
ALTER TABLE "RentReceipt" ADD CONSTRAINT "RentReceipt_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE INDEX "RentReceipt_matchedTxId_idx" ON "RentReceipt"("matchedTxId");
ALTER TABLE "RentReceipt" ADD CONSTRAINT "RentReceipt_matchedTxId_fkey"
  FOREIGN KEY ("matchedTxId") REFERENCES "BankTransaction"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Query optimization indices
CREATE INDEX "RentReceipt_tenantId_month_idx" ON "RentReceipt"("tenantId", "month");
CREATE INDEX "RentReceipt_paidAt_idx" ON "RentReceipt"("paidAt" DESC);

-- Comments
COMMENT ON TABLE "RentReceipt" IS 'Links bank transactions to tenant rent payments - double-entry ledger pattern';
COMMENT ON COLUMN "RentReceipt"."month" IS 'Period this payment applies to (YYYY-MM format)';
COMMENT ON COLUMN "RentReceipt"."matchedVia" IS 'How payment was matched: reference (exact code), amount+name (fuzzy), manual (admin entry)';
COMMENT ON COLUMN "RentReceipt"."partial" IS 'Whether this is a partial payment (amount < expected rent)';

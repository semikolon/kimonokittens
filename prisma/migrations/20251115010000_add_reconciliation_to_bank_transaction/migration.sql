-- Add reconciliation tracking columns to BankTransaction
-- These columns link bank transactions to rent receipts after payment matching

ALTER TABLE "BankTransaction" ADD COLUMN "reconciledAt" TIMESTAMP(3);
ALTER TABLE "BankTransaction" ADD COLUMN "rentReceiptId" TEXT;

-- Index for finding unreconciled transactions efficiently
CREATE INDEX "BankTransaction_reconciledAt_idx" ON "BankTransaction"("reconciledAt") WHERE "reconciledAt" IS NULL;

-- Comments
COMMENT ON COLUMN "BankTransaction"."reconciledAt" IS 'Timestamp when transaction was matched to a rent receipt';
COMMENT ON COLUMN "BankTransaction"."rentReceiptId" IS 'ID of the RentReceipt this transaction was matched to';

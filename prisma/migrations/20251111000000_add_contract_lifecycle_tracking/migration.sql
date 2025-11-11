-- Add lifecycle event tracking fields to SignedContract

-- Generation lifecycle tracking
ALTER TABLE "SignedContract"
  ADD COLUMN "generationStatus" TEXT DEFAULT 'pending',
  ADD COLUMN "generationStartedAt" TIMESTAMP(3),
  ADD COLUMN "generationCompletedAt" TIMESTAMP(3),
  ADD COLUMN "generationFailedAt" TIMESTAMP(3),
  ADD COLUMN "generationError" JSONB;

-- Validation lifecycle tracking
ALTER TABLE "SignedContract"
  ADD COLUMN "validationStatus" TEXT DEFAULT 'pending',
  ADD COLUMN "validationStartedAt" TIMESTAMP(3),
  ADD COLUMN "validationCompletedAt" TIMESTAMP(3),
  ADD COLUMN "validationFailedAt" TIMESTAMP(3),
  ADD COLUMN "validationErrors" JSONB;

-- Email delivery lifecycle tracking
ALTER TABLE "SignedContract"
  ADD COLUMN "emailDeliveryStatus" TEXT DEFAULT 'pending',
  ADD COLUMN "landlordEmailDelivered" BOOLEAN DEFAULT false,
  ADD COLUMN "tenantEmailDelivered" BOOLEAN DEFAULT false,
  ADD COLUMN "emailDeliveryFailedAt" TIMESTAMP(3),
  ADD COLUMN "emailDeliveryError" TEXT;

-- Add indices for event queries
CREATE INDEX "SignedContract_generationStatus_idx" ON "SignedContract"("generationStatus");
CREATE INDEX "SignedContract_validationStatus_idx" ON "SignedContract"("validationStatus");
CREATE INDEX "SignedContract_emailDeliveryStatus_idx" ON "SignedContract"("emailDeliveryStatus");

-- Add check constraints for status values
ALTER TABLE "SignedContract"
  ADD CONSTRAINT "SignedContract_generationStatus_check"
    CHECK ("generationStatus" IN ('pending', 'started', 'completed', 'failed')),

  ADD CONSTRAINT "SignedContract_validationStatus_check"
    CHECK ("validationStatus" IN ('pending', 'started', 'completed', 'failed')),

  ADD CONSTRAINT "SignedContract_emailDeliveryStatus_check"
    CHECK ("emailDeliveryStatus" IN ('pending', 'delivering', 'delivered', 'failed'));

-- Comments for clarity
COMMENT ON COLUMN "SignedContract"."generationStatus" IS 'PDF generation lifecycle: pending → started → completed/failed';
COMMENT ON COLUMN "SignedContract"."validationStatus" IS 'Document validation lifecycle: pending → started → completed/failed';
COMMENT ON COLUMN "SignedContract"."emailDeliveryStatus" IS 'Email delivery lifecycle: pending → delivering → delivered/failed';
COMMENT ON COLUMN "SignedContract"."generationError" IS 'JSONB structured error if generation failed: {code, message, details}';
COMMENT ON COLUMN "SignedContract"."validationErrors" IS 'JSONB array of validation errors from Zigned API';
COMMENT ON COLUMN "SignedContract"."emailDeliveryError" IS 'Error message if email delivery failed';

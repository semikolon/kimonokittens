-- Add rent reminder fields to Tenant table
ALTER TABLE "Tenant"
  ADD COLUMN "phoneE164" TEXT,  -- "+46701234567" (E.164 validated)
  ADD COLUMN "paydayStartDay" INTEGER NOT NULL DEFAULT 25,  -- 25 or 27
  ADD COLUMN "smsOptOut" BOOLEAN NOT NULL DEFAULT false;

-- Migrate existing phone numbers to E.164 format (Swedish numbers only)
-- Strip spaces, dashes, and other non-digit characters to handle messy input
UPDATE "Tenant"
SET "phoneE164" = CASE
  -- Already starts with +46, strip non-digits except leading +
  WHEN "phone" LIKE '+46%' THEN
    '+46' || REGEXP_REPLACE(SUBSTRING("phone" FROM 4), '[^0-9]', '', 'g')
  -- Swedish mobile (starts with 07), strip non-digits
  WHEN "phone" ~ '^0?7[0-9]' THEN
    '+46' || REGEXP_REPLACE(SUBSTRING("phone" FROM CASE WHEN "phone" LIKE '07%' THEN 2 ELSE 1 END), '[^0-9]', '', 'g')
  -- Other formats (keep null for manual validation)
  ELSE NULL
END
WHERE "phone" IS NOT NULL AND "phone" != '';

-- Add check constraint for E.164 format validation
ALTER TABLE "Tenant"
  ADD CONSTRAINT "Tenant_phoneE164_format_check"
    CHECK ("phoneE164" IS NULL OR "phoneE164" ~ '^\+[1-9]\d{1,14}$');

-- Add check constraint for payday range (1-31)
ALTER TABLE "Tenant"
  ADD CONSTRAINT "Tenant_paydayStartDay_range_check"
    CHECK ("paydayStartDay" >= 1 AND "paydayStartDay" <= 31);

-- Index for phone lookups
CREATE INDEX "Tenant_phoneE164_idx" ON "Tenant"("phoneE164");

-- Comments
COMMENT ON COLUMN "Tenant"."phoneE164" IS 'Phone number in E.164 format (e.g., +46701234567) for SMS delivery';
COMMENT ON COLUMN "Tenant"."paydayStartDay" IS 'Day of month when salary arrives (25 or 27) - determines first payment reminder timing';
COMMENT ON COLUMN "Tenant"."smsOptOut" IS 'Whether tenant has opted out of SMS reminders (legal requirement)';

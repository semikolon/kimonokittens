-- Track individual participants in signing workflow
CREATE TABLE "ContractParticipant" (
  "id" TEXT NOT NULL,
  "contractId" TEXT NOT NULL,
  "participantId" TEXT NOT NULL,  -- Zigned participant ID
  "name" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "personalNumber" TEXT NOT NULL,
  "role" TEXT NOT NULL DEFAULT 'signer',
  "status" TEXT NOT NULL DEFAULT 'pending',
  "signingUrl" TEXT,
  "signedAt" TIMESTAMP(3),
  "emailDelivered" BOOLEAN NOT NULL DEFAULT false,
  "emailDeliveredAt" TIMESTAMP(3),
  "emailDeliveryFailed" BOOLEAN NOT NULL DEFAULT false,
  "emailDeliveryError" TEXT,
  "identityEnforcementPassed" BOOLEAN,
  "identityEnforcementFailedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "ContractParticipant_pkey" PRIMARY KEY ("id")
);

-- Unique constraint: one participant record per Zigned participant
CREATE UNIQUE INDEX "ContractParticipant_participantId_key" ON "ContractParticipant"("participantId");

-- Foreign key to contract
CREATE INDEX "ContractParticipant_contractId_idx" ON "ContractParticipant"("contractId");
ALTER TABLE "ContractParticipant" ADD CONSTRAINT "ContractParticipant_contractId_fkey"
  FOREIGN KEY ("contractId") REFERENCES "SignedContract"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Query optimization indices
CREATE INDEX "ContractParticipant_personalNumber_idx" ON "ContractParticipant"("personalNumber");
CREATE INDEX "ContractParticipant_status_idx" ON "ContractParticipant"("status");

-- Check constraints
ALTER TABLE "ContractParticipant"
  ADD CONSTRAINT "ContractParticipant_status_check"
    CHECK ("status" IN ('pending', 'invited', 'viewed', 'signing', 'fulfilled', 'rejected'));

-- Comments
COMMENT ON TABLE "ContractParticipant" IS 'Individual signers in contract workflow (landlord, tenant, observers)';
COMMENT ON COLUMN "ContractParticipant"."participantId" IS 'Zigned participant ID from API';
COMMENT ON COLUMN "ContractParticipant"."personalNumber" IS 'Swedish personnummer for BankID validation';
COMMENT ON COLUMN "ContractParticipant"."status" IS 'Participant signing status from Zigned events';

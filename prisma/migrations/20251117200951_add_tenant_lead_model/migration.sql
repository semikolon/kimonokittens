-- CreateTable
CREATE TABLE "TenantLead" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "email" TEXT,
    "facebookId" TEXT,
    "phone" TEXT,
    "contactMethod" TEXT NOT NULL,
    "moveInFlexibility" TEXT NOT NULL,
    "moveInExtra" TEXT,
    "motivation" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending_review',
    "adminNotes" TEXT,
    "source" TEXT DEFAULT 'web_form',
    "ipAddress" TEXT NOT NULL,
    "userAgent" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "convertedToTenantId" TEXT,

    CONSTRAINT "TenantLead_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "TenantLead_convertedToTenantId_key" ON "TenantLead"("convertedToTenantId");

-- CreateIndex
CREATE INDEX "TenantLead_status_idx" ON "TenantLead"("status");

-- CreateIndex
CREATE INDEX "TenantLead_createdAt_idx" ON "TenantLead"("createdAt" DESC);

-- CreateIndex
CREATE INDEX "TenantLead_ipAddress_createdAt_idx" ON "TenantLead"("ipAddress", "createdAt");

-- AddForeignKey
ALTER TABLE "TenantLead" ADD CONSTRAINT "TenantLead_convertedToTenantId_fkey" FOREIGN KEY ("convertedToTenantId") REFERENCES "Tenant"("id") ON DELETE SET NULL ON UPDATE CASCADE;

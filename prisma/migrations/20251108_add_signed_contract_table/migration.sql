-- CreateTable: SignedContract
-- Stores Zigned signed PDFs and metadata in database instead of files
CREATE TABLE "SignedContract" (
  "id" TEXT NOT NULL,
  "tenantId" TEXT NOT NULL,
  "caseId" TEXT NOT NULL,
  "pdfUrl" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "landlordSigned" BOOLEAN NOT NULL DEFAULT false,
  "tenantSigned" BOOLEAN NOT NULL DEFAULT false,
  "landlordSignedAt" TIMESTAMP(3),
  "tenantSignedAt" TIMESTAMP(3),
  "completedAt" TIMESTAMP(3),
  "expiresAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "SignedContract_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SignedContract_caseId_key" ON "SignedContract"("caseId");

-- CreateIndex
CREATE INDEX "SignedContract_tenantId_idx" ON "SignedContract"("tenantId");

-- CreateIndex
CREATE INDEX "SignedContract_status_idx" ON "SignedContract"("status");

-- AddForeignKey
ALTER TABLE "SignedContract" ADD CONSTRAINT "SignedContract_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "Tenant" (
    "id" TEXT NOT NULL,
    "facebookId" TEXT,
    "name" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "avatarUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "roomAdjustment" DOUBLE PRECISION,
    "departureDate" TIMESTAMP(3),
    "startDate" TIMESTAMP(3),

    CONSTRAINT "Tenant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CoOwnedItem" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "purchaseDate" TIMESTAMP(3) NOT NULL,
    "value" DOUBLE PRECISION NOT NULL,

    CONSTRAINT "CoOwnedItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RentLedger" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "period" TIMESTAMP(3) NOT NULL,
    "amountDue" DOUBLE PRECISION NOT NULL,
    "amountPaid" DOUBLE PRECISION NOT NULL,
    "paymentDate" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RentLedger_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RentConfig" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "period" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "period_month" DATE GENERATED ALWAYS AS ((date_trunc('month'::text, period))::date) STORED,

    CONSTRAINT "RentConfig_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "_ItemOwners" (
    "A" TEXT NOT NULL,
    "B" TEXT NOT NULL,

    CONSTRAINT "_ItemOwners_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateIndex
CREATE UNIQUE INDEX "Tenant_facebookId_key" ON "Tenant"("facebookId");

-- CreateIndex
CREATE UNIQUE INDEX "Tenant_email_key" ON "Tenant"("email");

-- CreateIndex
CREATE INDEX "RentConfig_key_period_idx" ON "RentConfig"("key", "period" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "rentconfig_key_period_month_uniq" ON "RentConfig"("key", "period_month");

-- CreateIndex
CREATE INDEX "_ItemOwners_B_index" ON "_ItemOwners"("B");

-- AddForeignKey
ALTER TABLE "RentLedger" ADD CONSTRAINT "RentLedger_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_ItemOwners" ADD CONSTRAINT "_ItemOwners_A_fkey" FOREIGN KEY ("A") REFERENCES "CoOwnedItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "_ItemOwners" ADD CONSTRAINT "_ItemOwners_B_fkey" FOREIGN KEY ("B") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;


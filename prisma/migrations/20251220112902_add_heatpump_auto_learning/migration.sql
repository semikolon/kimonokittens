-- AlterTable
ALTER TABLE "public"."HeatpumpConfig" ADD COLUMN     "blockDistribution" TEXT NOT NULL DEFAULT '[2,2,2,2]',
ADD COLUMN     "lastAutoAdjustment" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "public"."HeatpumpAdjustment" (
    "id" TEXT NOT NULL,
    "adjustmentType" TEXT NOT NULL,
    "previousValue" TEXT NOT NULL,
    "newValue" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "overrideStats" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "HeatpumpAdjustment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "HeatpumpAdjustment_createdAt_idx" ON "public"."HeatpumpAdjustment"("createdAt" DESC);

-- CreateIndex
CREATE INDEX "HeatpumpAdjustment_adjustmentType_idx" ON "public"."HeatpumpAdjustment"("adjustmentType");

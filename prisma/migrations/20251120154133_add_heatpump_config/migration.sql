/*
  Warnings:

  - You are about to drop the column `reconciledAt` on the `BankTransaction` table. All the data in the column will be lost.
  - You are about to drop the column `rentReceiptId` on the `BankTransaction` table. All the data in the column will be lost.

*/
-- DropIndex
DROP INDEX "public"."RentReceipt_tenantId_idx";

-- DropIndex
DROP INDEX "public"."SmsEvent_tenantId_idx";

-- AlterTable
ALTER TABLE "public"."BankTransaction" DROP COLUMN "reconciledAt",
DROP COLUMN "rentReceiptId";

-- CreateTable
CREATE TABLE "public"."HeatpumpConfig" (
    "id" TEXT NOT NULL,
    "hoursOn" INTEGER NOT NULL DEFAULT 12,
    "maxPrice" DOUBLE PRECISION NOT NULL DEFAULT 2.2,
    "minTemp" DOUBLE PRECISION NOT NULL DEFAULT 20.0,
    "minHotwater" DOUBLE PRECISION NOT NULL DEFAULT 40.0,
    "emergencyPrice" DOUBLE PRECISION NOT NULL DEFAULT 0.3,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "HeatpumpConfig_pkey" PRIMARY KEY ("id")
);

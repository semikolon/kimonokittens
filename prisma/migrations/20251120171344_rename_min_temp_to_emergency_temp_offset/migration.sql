/*
  Warnings:

  - You are about to drop the column `minTemp` on the `HeatpumpConfig` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "public"."HeatpumpConfig" DROP COLUMN "minTemp",
ADD COLUMN     "emergencyTempOffset" DOUBLE PRECISION NOT NULL DEFAULT 1.0;

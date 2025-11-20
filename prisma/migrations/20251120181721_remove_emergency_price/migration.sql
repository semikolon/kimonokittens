/*
  Warnings:

  - You are about to drop the column `emergencyPrice` on the `HeatpumpConfig` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "public"."HeatpumpConfig" DROP COLUMN "emergencyPrice";

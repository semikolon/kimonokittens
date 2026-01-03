-- CreateTable
CREATE TABLE "public"."HeatpumpOverride" (
    "id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "temperature" DOUBLE PRECISION NOT NULL,
    "price" DOUBLE PRECISION NOT NULL,
    "hourOfDay" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "HeatpumpOverride_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "HeatpumpOverride_type_createdAt_idx" ON "public"."HeatpumpOverride"("type", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "HeatpumpOverride_hourOfDay_idx" ON "public"."HeatpumpOverride"("hourOfDay");

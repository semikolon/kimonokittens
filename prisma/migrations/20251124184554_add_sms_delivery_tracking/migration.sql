-- AlterTable
ALTER TABLE "public"."ContractParticipant" ADD COLUMN     "smsDelivered" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "smsDeliveredAt" TIMESTAMP(3);

<template>
  <div>
    <img :src="qrCodeUrl" alt="QR Code" class="qr-code">
    <p class="waiting-message">Väntar på inloggning...</p>
  </div>
</template>

<script>
export default {
  name: 'QRCode',
  props: {
    qrCode: {
      type: String,
      required: true
    }
  },
  computed: {
    qrCodeUrl() {
      return `${this.qrCode}?timestamp=${Date.now()}`;
    }
  }
}
</script>

<style scoped>
.qr-code {
  width: 40vh;
  height: 40vh;
}

.waiting-message {
  font-size: 2em;
  margin-top: 20px;
}
</style>

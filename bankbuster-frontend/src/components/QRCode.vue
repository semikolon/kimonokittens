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
  data() {
    return {
      timestamp: Date.now()
    }
  },
  computed: {
    qrCodeUrl() {
      return `${this.qrCode}?timestamp=${this.timestamp}`;
    }
  },
  methods: {
    refreshImage() {
      this.timestamp = Date.now();
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

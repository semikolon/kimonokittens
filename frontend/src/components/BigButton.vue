<template>
  <div>
    <button v-if="view === 'button'" class="big-button">
      {{ buttonText }}
    </button>
    <div v-else-if="view === 'qrCode'">
      <img :src="qrCode" alt="QR Code" class="qr-code">
      <p>Väntar på inloggning...</p>
    </div>
  </div>
</template>

<script>
export default {
  name: 'BigButton',
  props: {
    buttonText: {
      type: String,
      required: true
    },
    view: {
      type: String,
      required: true
    },
    qrCode: {
      type: String,
      required: false
    }
  }
}
</script>

<style scoped>
.big-button {
  width: 40vw;
  height: 40vh;
  font-size: 2em;
}

.qr-code {
  width: 40vh;
  height: 40vh;
}
</style>

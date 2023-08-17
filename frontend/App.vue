<template>
  <div id="app">
    <BigButton v-if="view === 'button'" @click="handleClick" />
    <div v-if="view === 'qrCode'">
      <!-- The QR code will go here -->
    </div>
    <div v-if="view === 'results'">
      <!-- The results table will go here -->
    </div>
    <div v-if="error" class="error-notification">
      Något gick fel.
    </div>
  </div>
</template>

<script>
import BigButton from './components/BigButton.vue'

export default {
  name: 'App',
  components: {
    BigButton,
  },
  data() {
    return {
      view: 'button',
      error: null,
      socket: null,
    }
  },
  created() {
    this.socket = new WebSocket('ws://localhost:6464/ws');
    this.socket.onmessage = this.handleMessage;
  },
  methods: {
    handleClick() {
      // Handle the button click
      this.view = 'qrCode';
      // If an error occurs, set this.error to the error message and this.view back to 'button'
    },
    handleMessage(event) {
      const message = event.data;
      if (message.startsWith('QR_UPDATE')) {
        // Refresh the QR code
      } else if (message.startsWith('FILES_RETRIEVED')) {
        // Update the view to show the results table
        this.view = 'results';
      }
    },
  },
}
</script>

<style scoped>
.error-notification {
  /* Add styles for the error notification */
}
</style>

<template>
  <div id="app">
    <BigButton v-if="view === 'button'" @click="handleClick" />
    <div v-if="view === 'qrCode'">
      <img :src="qrCode" alt="QR Code" class="qr-code">
      <p class="waiting-message">Väntar på inloggning...</p>
    </div>
    <div v-if="view === 'results'">
      <!-- The results table will go here -->
    </div>
    <div v-if="view === 'progress'">
      <progress max="100" :value="progress"></progress>
      <p>{{ progress }}% completed</p>
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
      progress: 0,
      qrCode: 'screenshots/qr_code.jpg',
      results: null,
    }
  },
  methods: {
    handleClick() {
      this.view = 'qrCode';
      this.socket.send('START');
    },
    handleMessage(event) {
      const message = event.data;
      if (message.startsWith('QR_UPDATE')) {
        this.qrCode = `screenshots/qr_code.jpg?timestamp=${Date.now()}`;
      } else if (message.startsWith('FILES_RETRIEVED')) {
        this.results = message.split('=')[1];
        this.view = 'results';
      } else if (message.startsWith('PROGRESS_UPDATE')) {
        this.progress = message.split('=')[1];
        this.view = 'progress';
      } else if (message.startsWith('ERROR')) {
        this.error = message;
        this.view = 'button';
      }
    },
  },
}
</script>

<style scoped>
.error-notification {
  /* Add styles for the error notification */
}

.qr-code {
  width: 40vh;
  height: 40vh;
}

.waiting-message {
  font-size: 2em;
  margin-top: 20px;
}
</style>

<style>
#app {
  font-family: Avenir, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  text-align: center;
  color: #2c3e50;
  margin-top: 60px;
}
</style>
<template>
  <div id="app">
    <BigButton v-if="view === 'button'" @click="handleClick" />
    <div v-if="view === 'qrCode'">
      <!-- The QR code will go here -->
    </div>
    <div v-if="view === 'results'">
      <!-- The results table will go here -->
    </div>
    <div v-if="view === 'progress'">
      <progress max="100" :value="progress"></progress>
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
    }
  },
  created() {
    this.socket = this.$socket;
    this.socket.onmessage = this.handleMessage;
  },
  methods: {
    handleClick() {
      // Handle the button click
      this.view = 'qrCode';
      // If an error occurs, set this.error to the error message and this.view back to 'button'
    },
    // Remove the handleMessage method
  },
}
</script>

<style scoped>
.error-notification {
  /* Add styles for the error notification */
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

<template>
  <div id="app">
    <BigButton v-if="view === 'button'" @click="handleClick" />
    <div v-if="view === 'qrCode'">
      <img :src="qrCode" alt="QR Code" class="qr-code">
      <p class="waiting-message">Väntar på inloggning...</p>
    </div>
    <div v-if="view === 'results'">
      <table class="table-auto">
        <thead>
          <tr>
            <th class="px-4 py-2">Debtor Name</th>
            <th class="px-4 py-2">Payment Date</th>
            <th class="px-4 py-2">Total Amount</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="result in results" :key="result.debtor_name">
            <td class="border px-4 py-2">{{ result.debtor_name }}</td>
            <td class="border px-4 py-2">{{ result.payment_date }}</td>
            <td class="border px-4 py-2">{{ result.total_amount }}</td>
          </tr>
        </tbody>
      </table>
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
      const message = JSON.parse(event.data);
      if (message.type === 'QR_UPDATE') {
        this.qrCode = `${message.qr_code_url}?timestamp=${Date.now()}`;
      } else if (message.type === 'FILES_RETRIEVED') {
        this.results = message.data;
        this.view = 'results';
      } else if (message.type === 'PROGRESS_UPDATE') {
        this.progress = message.progress;
        this.view = 'progress';
      } else if (message.type === 'ERROR') {
        this.error = message.error;
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
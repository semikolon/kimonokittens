<template>
  <div id="app">
    <BigButton v-if="view === 'button'" @click="handleClick" :buttonText="'Fetch payments'" />
    <QRCode v-if="view === 'qrCode'" :qrCode="qrCode" />
    <div v-if="view === 'results'">
      <input v-model="filterText" placeholder="Filter by name">
      <table class="table-auto">
        <thead>
          <tr>
            <th class="px-4 py-2" @click="sortBy('debtor_name')">Debtor Name</th>
            <th class="px-4 py-2" @click="sortBy('payment_date')">Payment Date</th>
            <th class="px-4 py-2" @click="sortBy('total_amount')">Total Amount</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="result in filteredResults" :key="result.debtor_name">
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
      <p>{{ error }}</p>
    </div>
    <div v-if="connectionError" class="connection-error-notification">
      <p>{{ connectionError }}</p>
    </div>
  </div>
</template>

<script>
import { inject } from 'vue';
import BigButton from './components/BigButton.vue'
import QRCode from './components/QRCode.vue'

export default {
  name: 'App',
  components: {
    BigButton,
    QRCode
  },
  setup() {
    const socket = inject('socket');
    
    return {
      socket
    };
  },
  data() {
    return {
      view: 'button',
      error: null,
      progress: 0,
      connectionError: null,
      qrCode: 'screenshots/qr_code.jpg',
      results: null,
      filterText: '',
      sortKey: '',
      sortOrders: {
        debtor_name: 1,
        payment_date: 1,
        total_amount: 1
      },
    }
  },
  computed: {
    filteredResults() {
      var sortKey = this.sortKey
      var filterKey = this.filterText && this.filterText.toLowerCase()
      var order = this.sortOrders[sortKey] || 1
      var results = this.results
      if (filterKey) {
        results = results.filter(function (row) {
          return Object.keys(row).some(function (key) {
            return String(row[key]).toLowerCase().indexOf(filterKey) > -1
          })
        })
      }
      if (sortKey) {
        results = results.slice().sort(function (a, b) {
          a = a[sortKey]
          b = b[sortKey]
          return (a === b ? 0 : a > b ? 1 : -1) * order
        })
      }
      return results
    }
  },
  methods: {
    handleClick() {
      this.view = 'qrCode';
      this.socket.send('START');
    },
    handleMessage(event) {
      let message;
      try {
        message = JSON.parse(event.data);
      } catch (error) {
        this.error = `Error parsing WebSocket message: ${error.message}`;
        return;
      }
      switch (message.type) {
        case 'QR_UPDATE':
          this.$refs.qrCodeComponent.refreshImage();
          break;
        case 'FILES_RETRIEVED':
          this.results = message.data;
          this.view = 'results';
          break;
        case 'PROGRESS_UPDATE':
          this.progress = message.progress;
          this.view = 'progress';
          break;
        case 'ERROR':
          this.error = message.error;
          this.view = 'button';
          break;
        default:
          this.error = `Unexpected message type: ${message.type}`;
      }
    },
    sortBy(key) {
      this.sortKey = key
      this.sortOrders[key] = this.sortOrders[key] * -1
    }
  },
}
</script>

<style scoped>
.error-notification,
.connection-error-notification {
  position: fixed;
  bottom: 0;
  width: 100%;
  background-color: #f56565;
  color: white;
  padding: 1em;
  text-align: center;
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

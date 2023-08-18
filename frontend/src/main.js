import { createApp, ref } from 'vue'
import App from './App.vue'
import './assets/tailwind.css'

const app = createApp(App)

app.config.globalProperties.$socket = ref(null)

app.mount('#app')

const websocketUrl = process.env.VUE_APP_WEBSOCKET_URL;
const socket = new WebSocket(websocketUrl);
let connectionEstablished = false;

// Set a timeout to close the connection if it isn't established within 5 seconds
const connectionTimeout = setTimeout(() => {
  if (!connectionEstablished) {
    socket.close();
    console.error('WebSocket connection timeout');
  }
}, 5000);

socket.onerror = function(error) {
  console.error(`WebSocket error: ${error}`);
};
socket.onopen = function() {
  connectionEstablished = true;
  clearTimeout(connectionTimeout);
};
socket.onclose = function(event) {
  console.log(`WebSocket connection closed: ${event.code}`);
};
socket.onmessage = function(event) {
  const message = event.data;
  if (message.startsWith('QR_UPDATE')) {
    const qrCodeUrl = message.split('=')[1];
    app.config.globalProperties.$socket.value.qrCode = `${qrCodeUrl}?timestamp=${Date.now()}`;
  } else if (message.startsWith('PROGRESS_UPDATE')) {
    app.config.globalProperties.$socket.value.progress = parseFloat(message.split('=')[1]);
    app.config.globalProperties.$socket.value.view = 'progress';
  } else if (message.startsWith('FILES_RETRIEVED')) {
    const data = message.split('=')[1];
    app.config.globalProperties.$socket.value.results = JSON.parse(data);
    app.config.globalProperties.$socket.value.view = 'results';
  } else if (message.startsWith('ERROR')) {
    const error = message.split('=')[1];
    app.config.globalProperties.$socket.value.error = error;
    app.config.globalProperties.$socket.value.view = 'error';
  }
};
app.config.globalProperties.$socket.value = socket;

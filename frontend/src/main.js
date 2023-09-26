import { createApp } from 'vue'
import App from './App.vue'
import './assets/tailwind.css'

const app = createApp(App)

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
  app.config.globalProperties.connectionError = `WebSocket connection error: ${error.code}`;
};

socket.onopen = function() {
  connectionEstablished = true;
  clearTimeout(connectionTimeout);
};

socket.onclose = function(event) {
  console.log(`WebSocket connection closed: ${event.code}`);
};

socket.onmessage = (event) => {
  const [key, value] = event.data.split('=');
  const { socket } = app.config.globalProperties;

  switch (key) {
    case 'QR_UPDATE':
      socket.value.qrCode = value;
      break;
    case 'PROGRESS_UPDATE':
      socket.value.progress = parseFloat(value);
      socket.value.view = 'progress';
      break;
    case 'FILES_RETRIEVED':
      socket.value.results = JSON.parse(value);
      socket.value.view = 'results';
      break;
    case 'ERROR':
      socket.value.error = value;
      socket.value.view = 'error';
      break;
  }
};

app.provide('socket', socket);
app.mount('#app');

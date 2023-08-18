import { createApp, ref } from 'vue'
import App from './App.vue'
import './assets/tailwind.css'

const app = createApp(App)

app.config.globalProperties.$socket = ref(null)

app.mount('#app')

const websocketUrl = process.env.VUE_APP_WEBSOCKET_URL;
const socket = new WebSocket(websocketUrl);
socket.onerror = function(error) {
  console.error(`WebSocket error: ${error}`);
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
      } else if (message.startsWith('ERROR')) {
        app.config.globalProperties.$socket.value.error = message;
        app.config.globalProperties.$socket.value.view = 'button';
      }
};
app.config.globalProperties.$socket.value = socket;

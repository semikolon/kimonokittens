import { createApp, ref } from 'vue'
import App from './App.vue'
import './assets/tailwind.css'

const app = createApp(App)

app.config.globalProperties.$socket = ref(null)

app.mount('#app')

const websocketUrl = process.env.VUE_APP_WEBSOCKET_URL || 'ws://localhost:6464/ws';
const websocketUrl = process.env.VUE_APP_WEBSOCKET_URL || 'ws://localhost:6464/ws';
const socket = new WebSocket(websocketUrl);
socket.onerror = function(error) {
  console.error(`WebSocket error: ${error}`);
};
socket.onclose = function(event) {
  console.log(`WebSocket connection closed: ${event.code}`);
};
app.config.globalProperties.$socket.value = socket;

app.config.globalProperties.$socket.value.onmessage = (event) => {
  const message = event.data
  if (message.startsWith('QR_UPDATE')) {
    // Refresh the QR code
  } else if (message.startsWith('FILES_RETRIEVED')) {
    // Update the view to show the results table
  } else if (message.startsWith('PROGRESS_UPDATE')) {
    const progress = message.split('=')[1];
    // Update the progress bar with the new progress value
    app.config.globalProperties.$progress.value = progress;
  }
}

app.config.globalProperties.$socket.value.onopen = () => {
  app.config.globalProperties.$socket.value.send('START')
}

import { createApp, ref } from 'vue'
import App from './App.vue'
import './assets/tailwind.css'

const app = createApp(App)

app.config.globalProperties.$socket = ref(null)

app.mount('#app')

const websocketUrl = process.env.VUE_APP_WEBSOCKET_URL;
const websocketUrl = process.env.VUE_APP_WEBSOCKET_URL;
const socket = new WebSocket(websocketUrl);
socket.onerror = function(error) {
  console.error(`WebSocket error: ${error}`);
};
socket.onclose = function(event) {
  console.log(`WebSocket connection closed: ${event.code}`);
};
app.config.globalProperties.$socket.value = socket;

// Remove the onmessage handler

app.config.globalProperties.$socket.value.onopen = () => {
  app.config.globalProperties.$socket.value.send('START')
}

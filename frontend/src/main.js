import { createApp, ref } from 'vue'
import App from './App.vue'
import './assets/tailwind.css'

const app = createApp(App)

app.config.globalProperties.$socket = ref(null)

app.mount('#app')

app.config.globalProperties.$socket.value = new WebSocket('ws://localhost:6464/ws')

app.config.globalProperties.$socket.value.onmessage = (event) => {
  const message = event.data
  if (message.startsWith('QR_UPDATE')) {
    // Refresh the QR code
  } else if (message.startsWith('FILES_RETRIEVED')) {
    // Update the view to show the results table
  }
}

app.config.globalProperties.$socket.value.onopen = () => {
  app.config.globalProperties.$socket.value.send('START')
}

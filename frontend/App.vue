<template>
  <div id="app">
    <BigButton v-if="!error" @click="handleClick" />
    <div v-if="error" class="error-notification">
      Något gick fel.
    </div>
    <!-- The results table will go here -->
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
      error: null,
    }
  },
  methods: {
    handleClick() {
      // Handle the button click
      // If an error occurs, set this.error to the error message
    },
  },
}
</script>

<style scoped>
.error-notification {
  /* Add styles for the error notification */
}
</style>

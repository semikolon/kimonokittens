<template>
  <button class="big-button">
    {{ buttonText }}
  </button>
</template>

<script>
export default {
  name: 'BigButton',
  props: {
    buttonText: {
      type: String,
      required: true
    }
  }
}
</script>

<style scoped>
.big-button {
  width: 40vw;
  height: 40vh;
  font-size: 2em;
  /* Add more styles as needed */
}
</style>

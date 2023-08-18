# Frontend for BankBuster

## Project setup
```
yarn install
```

### Compiles and hot-reloads for development
```
yarn serve
```

### Compiles and minifies for production
```
yarn build
```

### Lints and fixes files
```
yarn lint
```

### Customize configuration
See [Configuration Reference](https://cli.vuejs.org/config/).



## Description of code, so that GPT/Aider doesn't have to load too many heavy files

### BankBuster
The `BankBuster` class in `bank_buster.rb` is a web scraper that interacts with a bank's website to retrieve and parse payment files. It uses the Ferrum and Vessel libraries to automate browser interactions.

The `parse` method is the main entry point. It starts by filtering out non-essential network requests, accepts cookies, and initiates the login process. It then retrieves and parses the payment files, and resets the browser for potential reuse.

The `parse` method yields results at various stages of the process. These results are JSON objects with a `type` field that indicates the type of the result. The possible types are:

- `'QR_UPDATE'`: The QR code for login has been updated. The result includes the URL of the QR code image.
- `'PROGRESS_UPDATE'`: The progress of the file retrieval process has been updated. The result includes the current progress as a percentage.
- `'FILES_RETRIEVED'`: All files have been retrieved and parsed. The result includes the parsed data.
- `'ERROR'`: An error occurred. The result includes an error message.

### BankBusterHandler
The `BankBusterHandler` class in `handlers/bank_buster_handler.rb` is a WebSocket handler that uses an instance of `BankBuster` to handle incoming WebSocket messages. When it receives a `'START'` message, it calls the `parse` method of `BankBuster` and sends the results to the frontend as they become available..

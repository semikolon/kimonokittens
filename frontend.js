// When the frontend receives a message starting with "QR_UPDATE", it can refresh the QR code image using the timestamp trick:

if (message.startsWith("QR_UPDATE")) {
    const timestamp = message.split("=")[1];
    const imageUrl = `qr_code.jpg?timestamp=${timestamp}`;
    document.getElementById("qrCodeImage").src = imageUrl;
}

// When the frontend receives the processed data from BankPaymentsReader.parse_files, you can update the UI accordingly.
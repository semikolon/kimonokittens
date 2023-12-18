let outages = flow.get('outages') || [];
let lastUpdate = flow.get('last_update') || 0;
let currentTime = Date.now();
let thirtyMinutes = 30 * 60 * 1000;

// Update the last_update time to current
flow.set('last_update', currentTime);

// Check for an outage
if (currentTime - lastUpdate > thirtyMinutes) {
    outages.push(currentTime);
}

// Filter outages older than 72 hours
outages = outages.filter(time => currentTime - time < (72 * 60 * 60 * 1000));
flow.set('outages', outages);

msg.payload.outageCount = outages.length;
return msg;
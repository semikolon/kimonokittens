# Raspberry Pi to Dell Server Migration Plan

This document outlines the necessary steps to migrate the house's infrastructure services from the Raspberry Pi to the new Dell Linux server. The goal is to consolidate services onto the more powerful machine and simplify the overall setup.

## Services to Migrate

The following services, currently running on the Raspberry Pi, need to be moved:

1.  **Node-RED:**
    *   **Action:** Install Node-RED on the Dell server.
    *   **Action:** Export flows, credentials, and any custom nodes from the Raspberry Pi instance.
    *   **Action:** Import the configuration into the new Dell server instance.
    *   **Note:** This is the source for the `/data/temperature` endpoint, among others.

2.  **Cron Scripts:**
    *   **Action:** Identify all cron jobs related to the Kimonokittens project on the Raspberry Pi (`crontab -l`).
    *   **Action:** Replicate these cron jobs on the Dell server. This likely includes scripts for fetching data from external APIs (e.g., Strava, SL).

3.  **Systemd Services:**
    *   **Action:** Identify any custom `systemd` services running on the Pi (e.g., for `json_server.rb` or other daemons).
    *   **Action:** Re-create and enable these service files on the Dell server to ensure applications start on boot.

## Post-Migration Configuration Changes

Once the services have been successfully migrated and are running on the Dell server, the following code change must be made:

-   **Update Proxy Handler IP:**
    -   **File:** `handlers/proxy_handler.rb`
    -   **Action:** Update the hard-coded IP address for the Node-RED proxy target from the Raspberry Pi's IP to `localhost` or the Dell server's local IP.

This will ensure that the Agoo server, also running on the Dell, can correctly proxy requests to the local Node-RED instance. 
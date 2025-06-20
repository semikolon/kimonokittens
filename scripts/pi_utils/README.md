# Pi Utility Scripts

These scripts were originally used on the Raspberry Pi for monitoring and automation. Preserved here for reference and potential future use.

## Process Monitoring
- **`count_chromium.sh`** - Shell script to count Chromium browser processes
- **`count_processes.rb`** - Ruby script for general process counting and monitoring

## Job Scraping
- **`job_scraper_example.rb`** - Full-featured job scraping example
- **`job_scraper_simple_example.rb`** - Simplified job scraping template  

## TV/Media
- **`tv-stream.js`** - TV streaming utility (Node.js)

## Usage Notes
- These scripts were designed for the Pi environment (ARM, specific network setup)
- May require adaptation for other environments
- Originally used alongside the main kimonokittens web server
- See `../config/schedule.rb` for how some were scheduled via cron

## History
Migrated from `kimonokittens_pi/` backup during 2025-06-20 merge session. 
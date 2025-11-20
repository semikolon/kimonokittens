# Use this file to define all of your cron jobs via Whenever.
# Learn more: https://github.com/javan/whenever

# NOTES
# • Originally tuned for Raspberry Pi; kept paths relative so it works regardless of host.
# • Output is logged to `cron_log.log`, which is git-ignored (see .gitignore).
# • Requires `whenever` gem (already in Gemfile) — run `whenever --update-crontab` after deploy.

job_type :rbenv_exec, %Q{export PATH=~/.rbenv/shims:/usr/bin:$PATH; eval "$(rbenv init -)"; \
                         cd :path && timeout 3m bundle exec :task :output }

set :output, "#{Dir.pwd}/cron_log.log"
set :chronic_options, hours24: true

# NOTE: This Whenever configuration is NOT currently deployed in production.
# Production uses direct crontab entries (see docs/PRODUCTION_CRON_DEPLOYMENT.md).
# Keeping this file for potential future migration to Whenever gem (see TODO.md).

# Refresh Vattenfall electricity data every two hours
every 2.hours do
  rbenv_exec "ruby #{Dir.pwd}/vattenfall.rb"
end

#every 1.day, at: '16.22' do
#    rbenv_exec "ruby #{Dir.pwd}/vattenfall.rb"
#end

# Example of the direct cron line previously used on the Raspberry Pi for reference (kept commented):
# 0 0,6,12,18 * * * /bin/bash -l -c 'export PATH=~/.rbenv/shims:/usr/bin:$PATH; eval "$(rbenv init -)"; cd /home/pi/kimonokittens && timeout 3m bundle exec ruby /home/pi/kimonokittens/vattenfall.rb >> /home/pi/kimonokittens/cron_log.log 2>&1'


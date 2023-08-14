# Use this file to easily define all of your cron jobs.
# Learn more: http://github.com/javan/whenever
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron


# This is working on the Raspberry Pi
# 0 0,6,12,18 * * * /bin/bash -l -c 'export PATH=~/.rbenv/shims:/usr/bin:$PATH; eval "$(rbenv init -)"; cd /home/pi/kimonokittens && bundle exec ruby /home/pi/kimonokittens/vattenfall.rb >> /home/pi/kimonokittens/cron_log.log 2>&1'

job_type :rbenv_exec, %Q{export PATH=~/.rbenv/shims:/usr/bin:$PATH; eval "$(rbenv init -)"; \
                         cd :path && timeout 3m bundle exec :task :output }

set :output, "#{Dir.pwd}/cron_log.log"

set :chronic_options, hours24: true

every 4.hours do
    rbenv_exec "ruby #{Dir.pwd}/vattenfall.rb"
end

# every 1.day, at: '17.15' do
#     rbenv_exec "ruby #{Dir.pwd}/vattenfall.rb"
# end


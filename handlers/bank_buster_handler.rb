require_relative '../bank_buster'
require 'oj'
# require 'pry'  # Temporarily disabled due to gem conflict
require 'agoo'
require 'colorize'
require 'open3' # Added for Open3.popen3

class BankBusterHandler
  def initialize
    puts "Initializing BankBusterHandler..."
    # A BankBuster instance will be created on-demand for each job.
  end

  def call(env)
    if env['rack.upgrade?'] == :websocket
      env['rack.upgrade'] = self # Return this instance as the WebSocket handler so callbacks fire
      # DO NOT CHANGE THIS STATUS CODE! Agoo+Rack requires 101 for WebSocket upgrades.
      return [101, {}, []]
    end
    [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
  end

  def on_open(client)
    puts "BANKBUSTER WS: Connection opened."
  end

  def on_message(client, msg)
    puts "BANKBUSTER WS: Received message: #{msg}"

    if msg == 'START'
      puts "BANKBUSTER WS: Received start message, starting a new BankBuster job"
      # Send immediate acknowledgement so frontend knows handler is alive
      client.write(Oj.dump({ type: 'LOG', data: 'BankBuster job started on server...' }))
      
      # We will now run the scraper in a completely separate process to avoid
      # any possibility of it blocking the main Agoo server thread.
      # The output of the script, which is a stream of JSON objects, will be
      # piped directly to the WebSocket client.
      Thread.new do
        command = "bundle exec ruby bank_buster.rb"
        
        # Open3 allows us to capture stdout, stderr, and the thread
        Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
          # We don't need to send anything to the script's stdin
          stdin.close

          # Read from the script's stdout line by line
          stdout.each_line do |line|
            begin
              # The script outputs JSON, so we send it directly to the client.
              # We don't need to re-dump it.
              client.write(line)
              puts "BANKBUSTER STDOUT: #{line.strip}".cyan
            rescue => e
              puts "Error writing to client: #{e.message}".red
              break
            end
          end

          # Handle any errors from the script's stderr
          stderr.each_line do |line|
            error_message = { type: 'ERROR', error: 'Scraper STDERR', message: line.strip }
            client.write(Oj.dump(error_message))
            puts "BANKBUSTER STDERR: #{line.strip}".red
          end

          # Wait for the process to finish and check the exit status
          exit_status = wait_thr.value
          puts "BankBuster process finished with status: #{exit_status}."
          
          # Notify the client that the process has finished
          if exit_status.success?
            client.write(Oj.dump({ type: 'LOG', data: 'BankBuster process completed successfully.'}))
          else
            client.write(Oj.dump({ type: 'FATAL_ERROR', error: 'Scraper Process Failed', message: "Process exited with status #{exit_status.exitstatus}"}))
          end
        end
      rescue => e
        error_details = { type: 'FATAL_ERROR', error: e.class.name, message: e.message, backtrace: e.backtrace }
        puts "Error in BankBuster handler thread: #{error_details}".red
        client.write(Oj.dump(error_details))
      end
    end
  end

  def on_close(client)
    puts "BANKBUSTER WS: Closing socket connection."
  end
end
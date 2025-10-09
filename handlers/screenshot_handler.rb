# Screenshot Handler - Capture kiosk display via API
# Requires: scrot (install with: sudo apt-get install scrot)
#
# Usage: GET /api/screenshot
# Returns: PNG image of the current display
#
# This leverages the fact that puma_server.rb runs as kimonokittens user
# with DISPLAY access, avoiding all SSH/sudo authentication issues.

class ScreenshotHandler
  SCREENSHOTS_DIR = '/tmp/kimonokittens-screenshots'
  MAX_SCREENSHOTS = 10 # Keep last N screenshots

  def initialize
    FileUtils.mkdir_p(SCREENSHOTS_DIR)
  end

  def call(env)
    req = Rack::Request.new(env)

    case req.path_info
    when '/capture'
      handle_capture(req)
    when '/latest'
      handle_latest(req)
    else
      [404, {'Content-Type' => 'application/json'}, [Oj.dump({ error: 'Not found' })]]
    end
  end

  private

  def handle_capture(req)
    # Generate filename with timestamp
    timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
    filename = "kiosk-#{timestamp}.png"
    filepath = File.join(SCREENSHOTS_DIR, filename)

    # Take screenshot using scrot
    # Note: DISPLAY should already be set by systemd service, but we set it explicitly
    display = ENV['DISPLAY'] || ':0'
    cmd = "DISPLAY=#{display} scrot #{filepath}"

    begin
      result = system(cmd)

      unless result
        return [500, {'Content-Type' => 'application/json'}, [
          Oj.dump({
            error: 'Screenshot failed',
            message: 'scrot command failed. Is scrot installed? Run: sudo apt-get install scrot',
            command: cmd
          })
        ]]
      end

      # Verify file was created
      unless File.exist?(filepath)
        return [500, {'Content-Type' => 'application/json'}, [
          Oj.dump({ error: 'Screenshot file not created', path: filepath })
        ]]
      end

      # Cleanup old screenshots (keep last MAX_SCREENSHOTS)
      cleanup_old_screenshots

      # Return success with download URL
      [200, {'Content-Type' => 'application/json'}, [
        Oj.dump({
          success: true,
          filename: filename,
          path: filepath,
          size: File.size(filepath),
          download_url: "/api/screenshot/latest?download=#{filename}",
          view_url: "/api/screenshot/latest"
        })
      ]]

    rescue => e
      [500, {'Content-Type' => 'application/json'}, [
        Oj.dump({ error: e.message, backtrace: e.backtrace.first(5) })
      ]]
    end
  end

  def handle_latest(req)
    # Find most recent screenshot
    screenshots = Dir.glob(File.join(SCREENSHOTS_DIR, 'kiosk-*.png')).sort

    if screenshots.empty?
      return [404, {'Content-Type' => 'application/json'}, [
        Oj.dump({
          error: 'No screenshots available',
          message: 'Call /api/screenshot/capture first to take a screenshot'
        })
      ]]
    end

    latest = screenshots.last

    # Serve the image file
    [200,
     {
       'Content-Type' => 'image/png',
       'Content-Disposition' => "inline; filename=\"#{File.basename(latest)}\"",
       'Cache-Control' => 'no-cache'
     },
     [File.read(latest)]
    ]
  end

  def cleanup_old_screenshots
    screenshots = Dir.glob(File.join(SCREENSHOTS_DIR, 'kiosk-*.png')).sort

    if screenshots.length > MAX_SCREENSHOTS
      screenshots_to_delete = screenshots[0..-(MAX_SCREENSHOTS + 1)]
      screenshots_to_delete.each do |file|
        File.delete(file)
        puts "Deleted old screenshot: #{File.basename(file)}"
      end
    end
  end
end

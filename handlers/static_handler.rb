require 'logger'

class StaticHandler
  WWW_DIR = File.expand_path("../www", __FILE__)

  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
  end

  def call(req)
    path = File.join(WWW_DIR, req['PATH_INFO'])
    if File.exist?(path) && !File.directory?(path)
      @logger.info("Serving file: #{path}")
      serve_file(path)
    else
      @logger.warn("File not found: #{path}")
      [404, { 'Content-Type' => 'text/plain' }, [ "File not found." ]]
    end
  end

  private

  def serve_file(path)
    ext = File.extname(path)
    content_type = case ext
                   when '.html'
                     'text/html'
                   when '.css'
                     'text/css'
                   when '.js'
                     'application/javascript'
                   when '.png'
                     'image/png'
                   when '.jpg', '.jpeg'
                     'image/jpeg'
                   when '.gif'
                     'image/gif'
                   else
                     'application/octet-stream'
                   end
    [200, { 'Content-Type' => content_type }, [ File.read(path) ]]
  end
end
class StaticHandler
  WWW_DIR = File.expand_path("../www", __FILE__)

  def call(req)
    # ... existing code ...
  end

  private

  def serve_file(path)
    # ... existing code ...
  end
end

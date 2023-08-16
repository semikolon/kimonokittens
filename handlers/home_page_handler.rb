class HomePageHandler
  def initialize
    @content = File.read('www/index.html')
  end

  def call(req)
    [200, { 'Content-Type' => 'text/html' }, [ @content ]]
  end
end

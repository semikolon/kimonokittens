require 'agoo'

class TodosHandler
  def call(req)
    begin
      todos_content = File.read('household_todos.md')
      [200, { 'Content-Type' => 'text/plain' }, [todos_content]]
    rescue Errno::ENOENT
      # Fallback content if file doesn't exist
      fallback_content = "# Household Todos\n\n- Lägga upp annons är prio!\n- Klipp gräsmattan"
      [200, { 'Content-Type' => 'text/plain' }, [fallback_content]]
    rescue => e
      puts "Error reading todos: #{e.message}"
      [500, { 'Content-Type' => 'text/plain' }, ['Error reading todos']]
    end
  end
end
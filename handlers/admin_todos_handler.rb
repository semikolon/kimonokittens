# Handler for admin todo list management API
# Saves todos to Git (direct commits to main) and broadcasts via WebSocket
require 'json'
require 'rugged'
require_relative '../lib/admin_auth'

class AdminTodosHandler
  TODO_PATH = 'handbook/docs/household_todos.md'

  def call(env)
    req = Rack::Request.new(env)

    case req.request_method
    when 'POST'
      update_todos(req)
    when 'GET'
      get_todos
    else
      method_not_allowed
    end
  end

  private

  def get_todos
    content = File.read(TODO_PATH)
    items = parse_todos(content)

    json_response(200, { items: items })
  rescue Errno::ENOENT
    json_response(200, { items: [] })
  end

  def update_todos(req)
    # Verify admin authentication
    token = req.get_header('HTTP_X_ADMIN_TOKEN')
    unless AdminAuth.authorized?(token)
      return json_response(401, { error: 'Unauthorized' })
    end

    # Parse request body
    body = JSON.parse(req.body.read)
    items = body['items']

    unless items.is_a?(Array)
      return json_response(400, { error: 'items must be an array' })
    end

    # Sanitize items: strip whitespace, reject blanks
    items = items.map { |item| item.to_s.strip }.reject(&:empty?)

    # Build markdown content
    content = "# Household Todos\n\n" + items.map { |t| "- #{t}" }.join("\n") + "\n"

    # Check if content is unchanged (avoid empty commits)
    begin
      existing_content = File.read(TODO_PATH)
      if existing_content == content
        puts "AdminTodosHandler: No changes detected, skipping commit"
        return json_response(200, {
          success: true,
          items: items,
          unchanged: true
        })
      end
    rescue Errno::ENOENT
      # File doesn't exist yet, proceed with commit
    end

    # Commit to Git
    begin
      commit_oid = git_commit(content)
      puts "AdminTodosHandler: Committed todos (#{commit_oid[0..7]})"

      # Async push to origin
      Thread.new do
        success = system('git push origin master 2>&1')
        if success
          puts "AdminTodosHandler: Pushed to origin"
        else
          puts "AdminTodosHandler: Push failed (will retry on next push)"
        end
      end

      # Broadcast updated todos via WebSocket
      if defined?($data_broadcaster) && $data_broadcaster
        $data_broadcaster.broadcast_todos
        puts "AdminTodosHandler: Broadcasted todo update"
      end

      json_response(200, {
        success: true,
        items: items,
        commit: commit_oid[0..7]
      })
    rescue => e
      puts "AdminTodosHandler: Error - #{e.message}"
      json_response(500, { error: "Failed to save: #{e.message}" })
    end
  end

  def git_commit(content)
    repo = Rugged::Repository.new('.')

    # Get current main branch
    main_branch = repo.branches['master'] || repo.branches['main']
    raise "No master/main branch found" unless main_branch

    parent_commit = main_branch.target

    # Create new blob with content
    oid = repo.write(content, :blob)

    # Use in-memory index (NOT repo.index) to avoid leaving dirty staged state
    # if the commit fails. repo.index writes to .git/index on disk.
    index = Rugged::Index.new
    index.read_tree(parent_commit.tree)
    index.add(path: TODO_PATH, oid: oid, mode: 0100644)

    # Write tree and create commit
    tree_oid = index.write_tree(repo)

    commit_oid = Rugged::Commit.create(repo,
      tree: tree_oid,
      parents: [parent_commit],
      message: "Update household todos via admin dashboard",
      author: {
        name: 'Admin Dashboard',
        email: 'admin@kimonokittens.local',
        time: Time.now
      },
      committer: {
        name: 'Admin Dashboard',
        email: 'admin@kimonokittens.local',
        time: Time.now
      },
      update_ref: 'refs/heads/master'
    )

    commit_oid
  end

  def parse_todos(content)
    lines = content.split(/\r?\n/)
    items = []

    lines.each do |line|
      trimmed = line.strip
      if trimmed.start_with?('- ')
        items << trimmed[2..-1]
      end
    end

    items
  end

  def json_response(status, body)
    [status, { 'Content-Type' => 'application/json' }, [body.to_json]]
  end

  def method_not_allowed
    json_response(405, { error: 'Method not allowed' })
  end
end

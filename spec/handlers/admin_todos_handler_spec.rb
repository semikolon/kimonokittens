require_relative '../spec_helper'
require 'rspec'
require 'rack'
require 'fileutils'
require 'tmpdir'
require_relative '../../handlers/admin_todos_handler'
require_relative '../support/api_test_helpers'

RSpec.describe AdminTodosHandler do
  include ApiTestHelpers

  let(:handler) { AdminTodosHandler.new }

  # ==========================================================================
  # Unit Tests - Mock git operations, test HTTP handling
  # ==========================================================================
  describe 'HTTP handling' do
    describe 'GET /api/admin/todos' do
      let(:todo_content) { "# Household Todos\n\n- Item one\n- Item two\n" }

      before do
        allow(File).to receive(:read).with(AdminTodosHandler::TODO_PATH).and_return(todo_content)
      end

      it 'returns parsed todo items' do
        status, _, body = get_json(handler, '/api/admin/todos')

        expect(status).to eq(200)
        expect(body[:items]).to eq(['Item one', 'Item two'])
      end

      it 'returns empty array when file does not exist' do
        allow(File).to receive(:read).with(AdminTodosHandler::TODO_PATH).and_raise(Errno::ENOENT)

        status, _, body = get_json(handler, '/api/admin/todos')

        expect(status).to eq(200)
        expect(body[:items]).to eq([])
      end
    end

    describe 'POST /api/admin/todos' do
      let(:valid_token) { 'test-admin-token' }

      before do
        # Mock AdminAuth
        allow(AdminAuth).to receive(:authorized?).with(valid_token).and_return(true)
        allow(AdminAuth).to receive(:authorized?).with(nil).and_return(false)
        allow(AdminAuth).to receive(:authorized?).with('invalid').and_return(false)
      end

      it 'requires admin authentication' do
        env = build_post_env('/api/admin/todos', { items: ['Test'] })
        # No X-Admin-Token header

        status, _, body = handler.call(env)
        parsed = Oj.load(body.first, symbol_keys: true)

        expect(status).to eq(401)
        expect(parsed[:error]).to eq('Unauthorized')
      end

      it 'rejects invalid token' do
        env = build_post_env('/api/admin/todos', { items: ['Test'] }, 'invalid')

        status, _, body = handler.call(env)
        parsed = Oj.load(body.first, symbol_keys: true)

        expect(status).to eq(401)
        expect(parsed[:error]).to eq('Unauthorized')
      end

      it 'validates items is an array' do
        env = build_post_env('/api/admin/todos', { items: 'not an array' }, valid_token)

        status, _, body = handler.call(env)
        parsed = Oj.load(body.first, symbol_keys: true)

        expect(status).to eq(400)
        expect(parsed[:error]).to eq('items must be an array')
      end

      it 'sanitizes items - strips whitespace and rejects blanks' do
        allow(File).to receive(:read).with(AdminTodosHandler::TODO_PATH).and_return('')
        allow(File).to receive(:write)
        allow_any_instance_of(AdminTodosHandler).to receive(:git_commit).and_return('abc123')
        allow_any_instance_of(AdminTodosHandler).to receive(:push_with_retry).and_return(true)
        allow($data_broadcaster).to receive(:broadcast_todos) if defined?($data_broadcaster)

        env = build_post_env('/api/admin/todos', { items: ['  Valid  ', '', '   ', 'Also valid'] }, valid_token)

        status, _, body = handler.call(env)
        parsed = Oj.load(body.first, symbol_keys: true)

        expect(status).to eq(200)
        expect(parsed[:items]).to eq(['Valid', 'Also valid'])
      end

      it 'skips commit when content unchanged' do
        existing = "# Household Todos\n\n- Same item\n"
        allow(File).to receive(:read).with(AdminTodosHandler::TODO_PATH).and_return(existing)

        env = build_post_env('/api/admin/todos', { items: ['Same item'] }, valid_token)

        status, _, body = handler.call(env)
        parsed = Oj.load(body.first, symbol_keys: true)

        expect(status).to eq(200)
        expect(parsed[:unchanged]).to eq(true)
      end

      context 'when git operations succeed' do
        before do
          allow(File).to receive(:read).with(AdminTodosHandler::TODO_PATH).and_return('')
          allow(File).to receive(:write)
          allow_any_instance_of(AdminTodosHandler).to receive(:git_commit).and_return('abc12345')
          allow_any_instance_of(AdminTodosHandler).to receive(:push_with_retry).and_return(true)
        end

        it 'returns success with commit hash' do
          env = build_post_env('/api/admin/todos', { items: ['New item'] }, valid_token)

          status, _, body = handler.call(env)
          parsed = Oj.load(body.first, symbol_keys: true)

          expect(status).to eq(200)
          expect(parsed[:success]).to eq(true)
          expect(parsed[:commit]).to eq('abc12345')
        end

        it 'writes to filesystem before git commit' do
          write_order = []
          allow(File).to receive(:write) { write_order << :file_write }
          allow_any_instance_of(AdminTodosHandler).to receive(:git_commit) { write_order << :git_commit; 'abc123' }

          env = build_post_env('/api/admin/todos', { items: ['Test'] }, valid_token)
          handler.call(env)

          expect(write_order).to eq([:file_write, :git_commit])
        end
      end

      context 'when push fails' do
        before do
          allow(File).to receive(:read).with(AdminTodosHandler::TODO_PATH).and_return('')
          allow(File).to receive(:write)
          allow_any_instance_of(AdminTodosHandler).to receive(:git_commit).and_return('abc123')
          allow_any_instance_of(AdminTodosHandler).to receive(:push_with_retry).and_return(false)
          allow_any_instance_of(AdminTodosHandler).to receive(:system).and_return(true) # git checkout
        end

        it 'returns 500 error' do
          env = build_post_env('/api/admin/todos', { items: ['Test'] }, valid_token)

          status, _, body = handler.call(env)
          parsed = Oj.load(body.first, symbol_keys: true)

          expect(status).to eq(500)
          expect(parsed[:error]).to include('could not sync to remote')
        end

        it 'reverts filesystem to origin/master' do
          expect_any_instance_of(AdminTodosHandler).to receive(:system)
            .with("git checkout origin/master -- #{AdminTodosHandler::TODO_PATH} 2>&1")
            .and_return(true)

          env = build_post_env('/api/admin/todos', { items: ['Test'] }, valid_token)
          handler.call(env)
        end
      end

      context 'when git_commit raises error' do
        before do
          allow(File).to receive(:read).with(AdminTodosHandler::TODO_PATH).and_return('')
          allow(File).to receive(:write)
          allow_any_instance_of(AdminTodosHandler).to receive(:git_commit).and_raise(StandardError.new('Git error'))
          allow_any_instance_of(AdminTodosHandler).to receive(:system).and_return(true)
        end

        it 'returns 500 with error message' do
          env = build_post_env('/api/admin/todos', { items: ['Test'] }, valid_token)

          status, _, body = handler.call(env)
          parsed = Oj.load(body.first, symbol_keys: true)

          expect(status).to eq(500)
          expect(parsed[:error]).to include('Git error')
        end

        it 'reverts filesystem on error' do
          expect_any_instance_of(AdminTodosHandler).to receive(:system)
            .with("git checkout origin/master -- #{AdminTodosHandler::TODO_PATH} 2>&1")

          env = build_post_env('/api/admin/todos', { items: ['Test'] }, valid_token)
          handler.call(env)
        end
      end
    end

    describe 'unsupported methods' do
      it 'returns 405 for PUT' do
        env = {
          'PATH_INFO' => '/api/admin/todos',
          'REQUEST_METHOD' => 'PUT',
          'rack.input' => StringIO.new('')
        }

        status, _, body = handler.call(env)
        parsed = Oj.load(body.first, symbol_keys: true)

        expect(status).to eq(405)
        expect(parsed[:error]).to eq('Method not allowed')
      end
    end
  end

  # ==========================================================================
  # Integration Tests - Real git operations in isolated temp repo
  # ==========================================================================
  describe 'Git operations (isolated temp repo)', :integration do
    let(:temp_dir) { Dir.mktmpdir('admin_todos_test') }
    let(:todo_path) { File.join(temp_dir, 'handbook', 'docs', 'household_todos.md') }
    let(:handler_with_temp_repo) { AdminTodosHandlerTestable.new(temp_dir) }

    before do
      # Initialize a git repo in temp directory
      Dir.chdir(temp_dir) do
        system('git init --quiet')
        system('git config user.email "test@test.com"')
        system('git config user.name "Test"')

        # Create initial todo file
        FileUtils.mkdir_p('handbook/docs')
        File.write('handbook/docs/household_todos.md', "# Household Todos\n\n- Initial item\n")

        system('git add .')
        system('git commit -m "Initial commit" --quiet')
      end
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    describe '#git_commit' do
      it 'creates a commit with the new content' do
        new_content = "# Household Todos\n\n- New item\n"

        Dir.chdir(temp_dir) do
          commit_oid = handler_with_temp_repo.send(:git_commit, new_content)

          expect(commit_oid).to be_a(String)
          expect(commit_oid.length).to eq(40) # SHA-1 hash

          # Verify commit exists
          log = `git log --oneline -1`
          expect(log).to include('Update household todos')
        end
      end

      it 'syncs disk index to HEAD after commit (no staged changes)' do
        new_content = "# Household Todos\n\n- Updated item\n"

        Dir.chdir(temp_dir) do
          handler_with_temp_repo.send(:git_commit, new_content)

          # Disk index should match HEAD - no STAGED changes
          # (working tree will differ from HEAD since we don't write to filesystem)
          # git diff --cached shows only staged changes (index vs HEAD)
          staged_diff = `git diff --cached`
          expect(staged_diff.strip).to eq(''), "Expected no staged changes, got: #{staged_diff}"

          # Verify working tree differs (expected behavior)
          worktree_diff = `git diff`
          expect(worktree_diff).not_to be_empty, "Expected working tree to differ from HEAD"
        end
      end

      it 'working directory file is NOT modified by git_commit alone' do
        # git_commit only writes to git objects, not working directory
        # (the filesystem write happens separately in update_todos)
        original_content = File.read(todo_path)
        new_content = "# Household Todos\n\n- Different item\n"

        Dir.chdir(temp_dir) do
          handler_with_temp_repo.send(:git_commit, new_content)

          # File should still have original content (Rugged doesn't touch working dir)
          expect(File.read(todo_path)).to eq(original_content)
        end
      end
    end

    describe '#push_with_retry' do
      # Note: Can't easily test actual push without a remote
      # These test the retry logic with mocked system calls

      it 'returns true when push succeeds on first try' do
        allow(handler_with_temp_repo).to receive(:system)
          .with('git push origin master 2>&1').and_return(true)

        expect(handler_with_temp_repo.send(:push_with_retry)).to eq(true)
      end

      it 'retries with fetch+rebase on push failure' do
        call_count = 0
        allow(handler_with_temp_repo).to receive(:system) do |*args|
          cmd = args.last.is_a?(String) ? args.last : args.first
          call_count += 1

          case cmd
          when 'git push origin master 2>&1'
            call_count <= 1 ? false : true  # Fail first, succeed second
          when 'git fetch origin master 2>&1'
            true
          when /git rebase/
            true
          else
            true
          end
        end

        expect(handler_with_temp_repo.send(:push_with_retry)).to eq(true)
      end

      it 'aborts rebase and returns false on rebase conflict' do
        allow(handler_with_temp_repo).to receive(:system) do |*args|
          cmd = args.last.is_a?(String) ? args.last : args.first

          case cmd
          when 'git push origin master 2>&1'
            false
          when 'git fetch origin master 2>&1'
            true
          when /git rebase.*--no-edit/
            false  # Rebase fails
          when 'git rebase --abort 2>&1'
            true
          else
            true
          end
        end

        expect(handler_with_temp_repo.send(:push_with_retry)).to eq(false)
      end

      it 'uses non-interactive git flags to prevent TTY prompts' do
        allow(handler_with_temp_repo).to receive(:system).and_return(false, true, true, true)

        # Should use GIT_EDITOR and --no-edit flags
        expect(handler_with_temp_repo).to receive(:system).with(
          hash_including('GIT_EDITOR' => 'true', 'GIT_SEQUENCE_EDITOR' => 'true'),
          /git rebase --no-edit --no-stat/
        ).and_return(true)

        handler_with_temp_repo.send(:push_with_retry)
      end
    end
  end

  # ==========================================================================
  # Helper methods
  # ==========================================================================
  private

  def build_post_env(path, payload, token = nil)
    env = {
      'PATH_INFO' => path,
      'REQUEST_METHOD' => 'POST',
      'rack.input' => StringIO.new(Oj.dump(payload, mode: :compat))
    }
    env['HTTP_X_ADMIN_TOKEN'] = token if token
    env
  end
end

# Testable subclass that can use a custom working directory
class AdminTodosHandlerTestable < AdminTodosHandler
  def initialize(working_dir)
    @working_dir = working_dir
  end

  private

  def git_commit(content)
    repo = Rugged::Repository.new(@working_dir)

    main_branch = repo.branches['master'] || repo.branches['main']
    raise "No master/main branch found" unless main_branch

    parent_commit = main_branch.target

    oid = repo.write(content, :blob)

    index = Rugged::Index.new
    index.read_tree(parent_commit.tree)
    index.add(path: 'handbook/docs/household_todos.md', oid: oid, mode: 0100644)

    tree_oid = index.write_tree(repo)

    commit_oid = Rugged::Commit.create(repo,
      tree: tree_oid,
      parents: [parent_commit],
      message: "Update household todos via admin dashboard",
      author: { name: 'Test', email: 'test@test.com', time: Time.now },
      committer: { name: 'Test', email: 'test@test.com', time: Time.now },
      update_ref: 'refs/heads/master'
    )

    # Sync disk index to match HEAD
    repo.index.read_tree(repo.head.target.tree)
    repo.index.write

    commit_oid
  end
end

# Handoff Plan for Claude: Implementing the Git-Backed Proposal Workflow

**Objective:** Replace the current in-memory mock proposal system with a robust solution using Git for persistence. This involves reading from and writing to a local Git repository using the `rugged` Ruby gem.

**Current Situation:**
*   **Critical Issue:** The `Gemfile` is in a broken state due to a failed automated edit. Several gems are duplicated or incorrectly specified. This is the **first thing that must be fixed.**
*   The backend (`HandbookHandler`) uses a simple in-memory `@@proposals` array. This is what we are replacing.
*   The frontend (`ProposalList.tsx`, `Editor.tsx`) is fully functional but built to work with the mock backend.
*   A comprehensive test suite exists for both frontend and backend, but it currently tests the *mock* system. These tests will need significant updates.

---

## Detailed Step-by-Step Recovery and Implementation Plan

### Phase 1: Repair Environment and Dependencies

1.  **Restore `Gemfile` (CRITICAL FIRST STEP):**
    *   **Problem:** The file `Gemfile` is corrupted.
    *   **Action:** Replace the **entire contents** of `Gemfile` with the known-good configuration below. This version includes the `rugged` gem required for this task.
    *   **File:** `Gemfile`
    *   **Content:**
        ```ruby
        source 'https://rubygems.org'

        gem 'agoo', '2.15.3'
        gem 'json'
        gem 'pg'
        gem 'pry'
        gem 'pinecone-client'
        gem 'ruby-openai'
        gem 'puma'
        gem 'rspec', '~> 3.0'
        gem 'rack-test'
        gem 'rugged'

        group :development do
          gem 'listen', '~> 3.8'
        end
        ```

2.  **Install Dependencies:**
    *   **Problem:** The `Gemfile.lock` is out of sync with the corrected `Gemfile`.
    *   **Action:** Run `bundle install` in the terminal from the project root. This will resolve all dependencies and create a new, correct `Gemfile.lock`.
    *   **Command:** `bundle install`

### Phase 2: Backend - Git-based Proposal Logic (`handlers/handbook_handler.rb`)

The goal is to remove all references to `@@proposals` and `@@next_id`, and replace them with `Rugged` Git operations.

1.  **Initialize Rugged Repository:**
    *   At the top of the `HandbookHandler` class, add a helper method to access the repository. The server runs from the project root, so the path is simply `.`
    *   **Code Snippet:**
        ```ruby
        def self.repo
          @repo ||= Rugged::Repository.new('.')
        end
        ```

2.  **Re-implement `GET /api/handbook/proposals`:**
    *   This endpoint must now list branches from Git instead of reading from the old array.
    *   **Logic:**
        1.  Use `self.class.repo.branches.each("proposals/*")` to iterate over all proposal branches.
        2.  For each `branch`, construct a proposal object:
            *   `id`: The full, URL-safe branch name (e.g., `proposals/user/12345-some-change`).
            *   `description`: A human-readable description parsed from the branch name.
            *   `author`: The author's name, parsed from the branch name.
            *   `approvals`: This is tricky. A simple approach is to look for `.approval.{user}` files in the branch's latest commit tree.
        3.  Return the list of these objects as JSON.

3.  **Re-implement `POST /api/handbook/proposals`:**
    *   This endpoint must now create a new branch with a commit containing the proposed change.
    *   **Logic:**
        1.  Get the latest commit from the `main` branch. This will be the parent of our new commit.
        2.  Generate a unique and descriptive branch name (e.g., `proposals/#{params['author']}/#{Time.now.to_i}-update-readme`).
        3.  Create an in-memory index, add the updated file content (from `params['content']`) at the correct `page_path` (from `params['page_path']`), and write that index to a tree.
        4.  Create a new commit object with the new tree, the parent commit, and a descriptive message.
        5.  Create the new branch pointing to this new commit.

4.  **Re-implement `POST /api/handbook/proposals/:id/approve`:**
    *   The `:id` parameter is now the branch name of the proposal.
    *   **Logic:**
        1.  Find the proposal branch using the `id`.
        2.  Create a new commit on that branch which adds an empty approval file (e.g., `.approval.#{params['approver']}`).
        3.  Count the number of approval files in the new commit's tree.
        4.  **If approvals >= 2:**
            *   Attempt a merge into `main`. Use `repo.merge_commits` to get the resulting index.
            *   Check `index.conflicts?`.
            *   **If no conflicts:** Write the merge commit to the repository and update the `main` branch reference. Then, delete the proposal branch.
            *   **If conflicts:** Do nothing further. Return a status to the client indicating a conflict that requires manual developer intervention.

### Phase 3: Update Test Suites

Your final task is to ensure the application is still robust by updating the tests.

1.  **Backend Specs (`spec/handbook_handler_spec.rb`):**
    *   **Strategy:** The most important change is to stop interacting with the `@@proposals` array and instead mock the `Rugged` gem's objects and methods.
    *   Use `instance_double(Rugged::Repository)` and `instance_double(Rugged::Branch)`.
    *   Stub the `HandbookHandler.repo` method to return your mock repository.
    *   **Key Tests to Update/Create:**
        *   `GET /proposals`: Mock `repo.branches.each` to yield mock branches.
        *   `POST /proposals`: Mock the sequence of calls for creating a branch and commit.
        *   `POST .../approve` (1st approval): Verify it commits an approval file.
        *   `POST .../approve` (2nd approval, clean merge): Mock a successful, conflict-free merge.
        *   `POST .../approve` (2nd approval, with conflict): Mock a conflicted index from the merge method and ensure the backend handles it gracefully.

2.  **Frontend Tests (`handbook/frontend/src/**/*.test.tsx`):**
    *   The `fetch` mocks in the tests need to be updated to reflect the new API responses.
    *   Proposal IDs in mock data should now look like Git branch names.
    *   Add a test case for how `ProposalList.tsx` renders a proposal that has a merge conflict.

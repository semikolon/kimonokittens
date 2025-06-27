# Kimonokittens Master Plan (Detailed)

This document provides a detailed, step-by-step implementation plan for the Kimonokittens monorepo projects. It is designed to be executed by an AI assistant with minimal context loss. Execute tasks sequentially unless marked as `(BLOCKED)`.

---

## Phase 1: Foundational Data Structures

**Goal:** Define the core data models for the handbook before any code is written.

- [x] **(AI)** Create this master plan `TODO.md` to track high-level progress.
- [x] **(AI)** Update `handbook/docs/agreements.md` with co-ownership details.
- [ ] **(USER)** Locate existing rent API implementation notes from Mac Mini. *(This is a prerequisite for all financial tasks)*.
- [x] **(AI) Task 1.1: Define Prisma Schema**
    - [x] Create a new directory: `handbook/prisma`.
    - [x] Create a new file: `handbook/prisma/schema.prisma`.
    - [x] Edit `handbook/prisma/schema.prisma` and add the following content. This defines the database connection and the models for tenants and co-owned items. The `RentLedger` is commented out as it's blocked.
      ```prisma
      // This is your Prisma schema file,
      // learn more about it in the docs: https://pris.ly/d/prisma-schema

      generator client {
        provider = "prisma-client-js"
      }

      datasource db {
        provider = "postgresql"
        url      = env("DATABASE_URL") // The connection URL will be provided later
      }

      model Tenant {
        id           String        @id @default(cuid())
        name         String
        email        String        @unique
        avatarUrl    String?
        createdAt    DateTime      @default(now())
        updatedAt    DateTime      @updatedAt
        coOwnedItems CoOwnedItem[] @relation("ItemOwners")

        // rentLedger   RentLedger[]
      }

      model CoOwnedItem {
        id           String   @id @default(cuid())
        name         String
        description  String?
        purchaseDate DateTime
        value        Float // Original value in SEK
        owners       Tenant[] @relation("ItemOwners")
      }

      /*
      // BLOCKED until user provides rent calculation logic
      model RentLedger {
        id          String   @id @default(cuid())
        tenantId    String
        tenant      Tenant   @relation(fields: [tenantId], references: [id])
        period      DateTime // e.g., 2025-01-01 for Jan 2025
        amountDue   Float
        amountPaid  Float
        paymentDate DateTime?
        createdAt   DateTime @default(now())
      }
      */
      ```

---

## Phase 2: Handbook Frontend Scaffolding

**Goal:** Create a functional, non-interactive frontend shell with all necessary libraries and components.

- [x] **(AI) Task 2.1: Initialize Vite Project**
    - [x] In the terminal, run `cd handbook`.
    - [x] Run `npm create vite@latest frontend -- --template react-ts`.
- [x] **(AI) Task 2.2: Install Core Dependencies**
    - [x] Run `cd frontend`.
    - [x] Run `npm install`.
- [x] **(AI) Task 2.3: Set up Tailwind CSS**
    - [x] Run `npm install -D tailwindcss postcss autoprefixer`.
    - [x] Run `npx tailwindcss init -p`. This will create `tailwind.config.js` and `postcss.config.js`.
    - [x] Edit `tailwind.config.js` to add paths to all template files:
      ```javascript
      /** @type {import('tailwindcss').Config} */
      export default {
        content: [
          "./index.html",
          "./src/**/*.{js,ts,jsx,tsx}",
        ],
        theme: {
          extend: {},
        },
        plugins: [],
      }
      ```
    - [x] Edit `handbook/frontend/src/index.css` and replace its content with the `@tailwind` directives:
      ```css
      @tailwind base;
      @tailwind components;
      @tailwind utilities;
      ```
- [x] **(AI) Task 2.4: Install UI & Editor Dependencies**
    - [x] Run `npm install @radix-ui/react-dialog @radix-ui/react-popover`.
    - [x] Run `npm install @tiptap/react @tiptap/pm @tiptap/starter-kit`.
- [x] **(AI) Task 2.5: Create Placeholder Components**
    - [x] Create directory `handbook/frontend/src/components`.
    - [x] Create `handbook/frontend/src/components/WikiPage.tsx` with this content:
      ```tsx
      import React from 'react';

      interface WikiPageProps {
        title: string;
        content: string; // This will later be HTML from TipTap
      }

      export const WikiPage: React.FC<WikiPageProps> = ({ title, content }) => {
        return (
          <article className="prose lg:prose-xl">
            <h1>{title}</h1>
            <div dangerouslySetInnerHTML={{ __html: content }} />
          </article>
        );
      };
      ```
    - [x] Create `handbook/frontend/src/components/EditToolbar.tsx` with this content:
      ```tsx
      import React from 'react';
      import { Editor } from '@tiptap/react';

      interface EditToolbarProps {
        editor: Editor | null;
      }

      export const EditToolbar: React.FC<EditToolbarProps> = ({ editor }) => {
        if (!editor) {
          return null;
        }

        return (
          <div className="border border-gray-300 rounded-t-lg p-2">
            <button
              onClick={() => editor.chain().focus().toggleBold().run()}
              className={editor.isActive('bold') ? 'is-active' : ''}
            >
              Bold
            </button>
            {/* Add more buttons for italic, headings, etc. */}
          </div>
        );
      };
      ```
- [ ] **(BLOCKED) Task 2.6: Create `<RentPanel/>` component.** This depends on the user's notes.

---

## Phase 3: Backend & AI Pipeline Scaffolding

**Goal:** Define the backend API contract with mock data and build the script to populate our AI's knowledge base.

- [x] **(AI) Task 3.1: Add `pinecone-client` to Gemfile**
    - [x] Edit the root `Gemfile` and add `gem 'pinecone-client', '~> 0.1'`.
    - [x] Run `bundle install` in the terminal.
- [x] **(AI) Task 3.2: Scaffold API Routes**
    - [x] Edit `json_server.rb`. Add a new handler class at the end of the file.
      ```ruby
      class HandbookHandler < WEBrick::HTTPServlet::AbstractServlet
        def do_GET(req, res)
          res['Content-Type'] = 'application/json'
          
          # Mock API for fetching a single page
          if req.path.match(%r{/api/handbook/pages/(\w+)})
            slug = $1
            res.body = {
              title: "Mock Page: #{slug.capitalize}",
              content: "<h1>#{slug.capitalize}</h1><p>This is mock content for the page.</p>"
            }.to_json
            return
          end

          # Mock API for fetching proposals
          if req.path == '/api/handbook/proposals'
            res.body = [
              { id: 1, title: 'Proposal 1', author: 'Fredrik' },
              { id: 2, title: 'Proposal 2', author: 'Rasmus' }
            ].to_json
            return
          end

          res.status = 404
          res.body = { error: 'Not Found' }.to_json
        end
        
        def do_POST(req, res)
            # Mock API for creating a proposal
            if req.path == '/api/handbook/proposals'
                puts "Received proposal: #{req.body}"
                res['Content-Type'] = 'application/json'
                res.body = { status: 'success', message: 'Proposal received' }.to_json
                return
            end
            
            res.status = 404
            res.body = { error: 'Not Found' }.to_json
        end
      end
      ```
    - [x] In `json_server.rb`, find where other handlers are mounted (e.g., `server.mount "/api/...", ...`) and add the new handler:
      ```ruby
      server.mount "/api/handbook", HandbookHandler
      ```
- [x] **(AI) Task 3.3: Implement RAG Indexing Script**
    - [x] Create `handbook/scripts/index_documents.rb` with the following content. This script connects to Pinecone and indexes the content of our handbook documents.
      ```ruby
      require 'pinecone'
      require 'dotenv/load'

      # Configuration
      PINECONE_INDEX_NAME = 'kimonokittens-handbook'
      DOCS_PATH = File.expand_path('../../docs', __FILE__)
      # Standard dimension for OpenAI's text-embedding-ada-002
      VECTOR_DIMENSION = 1536 

      def init_pinecone
        Pinecone.configure do |config|
          config.api_key  = ENV.fetch('PINECONE_API_KEY')
          # NOTE: The environment for Pinecone is found in the Pinecone console
          # It's usually something like "gcp-starter" or "us-west1-gcp"
          config.environment = ENV.fetch('PINECONE_ENVIRONMENT') 
        end
      end

      def main
        init_pinecone
        pinecone = Pinecone::Client.new
        
        # 1. Create index if it doesn't exist
        unless pinecone.index(PINECONE_INDEX_NAME).describe_index_stats.success?
          puts "Creating Pinecone index '#{PINECONE_INDEX_NAME}'..."
          pinecone.create_index(
            name: PINECONE_INDEX_NAME,
            dimension: VECTOR_DIMENSION,
            metric: 'cosine'
          )
        end
        index = pinecone.index(PINECONE_INDEX_NAME)

        # 2. Read documents and prepare vectors
        vectors_to_upsert = []
        Dir.glob("#{DOCS_PATH}/*.md").each do |file_path|
          puts "Processing #{File.basename(file_path)}..."
          content = File.read(file_path)
          
          # Split content into chunks (by paragraph)
          chunks = content.split("\n\n").reject(&:empty?)
          
          chunks.each_with_index do |chunk, i|
            # FAKE EMBEDDING: In a real scenario, you would call an embedding API here.
            # For now, we generate a random vector.
            fake_embedding = Array.new(VECTOR_DIMENSION) { rand(-1.0..1.0) }
            
            vectors_to_upsert << {
              id: "#{File.basename(file_path, '.md')}-#{i}",
              values: fake_embedding,
              metadata: {
                file: File.basename(file_path),
                text: chunk[0..200] # Store a snippet of the text
              }
            }
          end
        end
        
        # 3. Upsert vectors to Pinecone
        puts "Upserting #{vectors_to_upsert.length} vectors to Pinecone..."
        index.upsert(vectors: vectors_to_upsert)
        puts "Done!"
      end

      main if __FILE__ == $0
      ```
    - [x] Add a note to the user: A `PINECONE_ENVIRONMENT` variable will need to be added to the environment for the script to run.

---

## Phase 4: Approval Workflow Implementation (UI & Mock Backend)

**Goal:** Build the user interface for proposing and approving changes, backed by a stateful mock API.

- [x] **(AI) Task 4.1: Enhance the Mock Backend to be Stateful**
    - [x] Edit `handlers/handbook_handler.rb` at the top of the `HandbookHandler` class to initialize: `@proposals = []` and `@next_proposal_id = 1`.
    - [x] Modify `do_POST` on `/api/handbook/proposals` to parse JSON, create proposal hash with `{ id: @next_proposal_id, title: "Proposal for #{Time.now.strftime('%Y-%m-%d')}", content: parsed_body['content'], approvals: 0 }`, add to array, increment ID, return new proposal as JSON.
    - [x] Modify `do_GET` on `/api/handbook/proposals` to return the `@proposals` array as JSON.
    - [x] Add route for `POST /api/handbook/proposals/(\d+)/approve` that finds proposal by ID, increments `:approvals` count, returns updated proposal as JSON.
- [x] **(AI) Task 4.2: Build Frontend UI for Proposals**
    - [x] Create `handbook/frontend/src/components/ProposalList.tsx` that fetches from `/api/handbook/proposals`, stores in `useState`, maps over proposals to show title/approval count, has "Approve" button that POSTs to approve endpoint.
    - [x] Create `handbook/frontend/src/components/Editor.tsx` using TipTap's `useEditor` hook with `StarterKit`, renders `EditToolbar` and `EditorContent`, has "Save Proposal" button that POSTs `editor.getHTML()` to `/api/handbook/proposals`.
    - [x] Update `handbook/frontend/src/App.tsx` to remove default Vite content, add state for showing WikiPage vs Editor, render ProposalList component always visible.

## Phase 5: AI Query Implementation

**Goal:** Connect the RAG pipeline to a real UI, using a real embedding model and LLM.

- [x] **(AI) Task 5.1: Update RAG Script for Real Embeddings**
    - [x] Add `ruby-openai` gem to Gemfile and run `bundle install`.
    - [x] Edit `handbook/scripts/index_documents.rb` to initialize OpenAI client, replace fake embeddings with real API calls to `text-embedding-3-small`, add error handling and rate limiting.
- [x] **(AI) Task 5.2: Create AI Query Backend Endpoint**
    - [x] Edit `handlers/handbook_handler.rb` to add route for `POST /api/handbook/query` that: parses question, embeds it, queries Pinecone for top results, constructs prompt with context, calls OpenAI chat completion, returns AI response.
- [x] **(AI) Task 5.3: Build Frontend UI for AI Queries**
    - [x] Create `handbook/frontend/src/components/QueryInterface.tsx` with text input, submit button, loading state, displays AI answer.
    - [x] Update `handbook/frontend/src/App.tsx` to include QueryInterface component.

## Phase 6: Testing

**Goal:** Ensure the application is robust and reliable with a comprehensive test suite.

- [x] **(AI) Task 6.1: Implement Backend Specs**
    - [x] Add `rspec` and `rack-test` to the Gemfile.
    - [x] Create `spec/handbook_handler_spec.rb` to test the mock API, covering proposal CRUD, approvals, and mocked AI queries.
- [x] **(AI) Task 6.2: Implement Frontend Specs**
    - [x] Add `vitest` and `@testing-library/react` to `package.json`.
    - [x] Configure Vite for testing with a `jsdom` environment.
    - [x] Create unit tests for `WikiPage` and `ProposalList` components.

## Phase 7: Core Logic Implementation

**Goal:** Connect remaining pieces and implement production features.

- [ ] **(USER)** Set up voice assistant hardware (Dell Optiplex, Google Homes).
- [ ] **(BLOCKED)** Implement financial calculations and link `RentLedger` to the UI.
- [ ] **(AI) Task 7.1: Implement Git-Backed Approval Workflow**
    - [ ] Add the `rugged` gem to the `Gemfile` for Git operations from Ruby.
    - [ ] Modify the `HandbookHandler` to create a new branch (e.g., `proposal/some-change`) when a proposal is submitted.
    - [ ] On approval, use `rugged` to merge the proposal branch into `master`.
    - [ ] **Conflict-Safety:** Implement a "dry-run" merge check to detect potential conflicts before enabling the merge button in the UI. The UI should show a warning if conflicts are found.
- [ ] Set up proper authentication and user management.

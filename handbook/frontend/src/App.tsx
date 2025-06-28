import React, { useState } from 'react';
import { ProposalList } from './components/ProposalList';
import { Editor } from './components/Editor';
import { WikiPage } from './components/WikiPage';
import { QueryInterface } from './components/QueryInterface';
import './App.css';

function App() {
  const [currentView, setCurrentView] = useState<'wiki' | 'editor'>('wiki');

  return (
    <div className="min-h-screen">
      <header className="bg-purple-50/80 backdrop-blur-sm border-b border-purple-200 sticky top-0 z-10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            <h1 className="text-xl font-semibold text-purple-900">
              Kimonokittens Handbook
            </h1>
            <nav className="flex items-center gap-2">
              <button
                onClick={() => setCurrentView('wiki')}
                className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                  currentView === 'wiki'
                    ? 'bg-orange-500 text-white'
                    : 'text-purple-700 hover:bg-purple-100'
                }`}
              >
                View Content
              </button>
              <button
                onClick={() => setCurrentView('editor')}
                className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                  currentView === 'editor'
                    ? 'bg-orange-500 text-white'
                    : 'text-purple-700 hover:bg-purple-100'
                }`}
              >
                Create Proposal
              </button>
            </nav>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-12">
          {/* Main content area */}
          <div className="lg:col-span-2 bg-white p-8 rounded-lg border border-purple-200 shadow-sm">
            {currentView === 'wiki' ? (
              <WikiPage
                title="Welcome to the Handbook"
                content="<p>This is the Kimonokittens collective handbook. Use the navigation above to create proposals or view existing content.</p><p>The approval workflow is now active - you can create proposals and approve them!</p><p>You can also ask questions to the House AI in the sidebar. It will search through our documents to provide answers.</p>"
              />
            ) : (
              <div>
                <h2 className="text-2xl font-bold mb-4 text-purple-900">Create a New Proposal</h2>
                <Editor />
              </div>
            )}
          </div>

          {/* Sidebar with proposals and AI */}
          <div className="lg:col-span-1 space-y-8">
            <QueryInterface />
            <ProposalList />
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;

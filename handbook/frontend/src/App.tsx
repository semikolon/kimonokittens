import React, { useState } from 'react';
import { ProposalList } from './components/ProposalList';
import { Editor } from './components/Editor';
import { WikiPage } from './components/WikiPage';
import { QueryInterface } from './components/QueryInterface';
import './App.css';

function App() {
  const [currentView, setCurrentView] = useState<'wiki' | 'editor'>('wiki');

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            <h1 className="text-2xl font-bold text-gray-900">
              Kimonokittens Handbook
            </h1>
            <nav className="flex gap-4">
              <button
                onClick={() => setCurrentView('wiki')}
                className={`px-4 py-2 rounded ${
                  currentView === 'wiki'
                    ? 'bg-blue-500 text-white'
                    : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
                }`}
              >
                View Pages
              </button>
              <button
                onClick={() => setCurrentView('editor')}
                className={`px-4 py-2 rounded ${
                  currentView === 'editor'
                    ? 'bg-blue-500 text-white'
                    : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
                }`}
              >
                Create Proposal
              </button>
            </nav>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Main content area */}
          <div className="lg:col-span-2">
            {currentView === 'wiki' ? (
              <WikiPage
                title="Welcome to the Handbook"
                content="<p>This is the Kimonokittens collective handbook. Use the navigation above to create proposals or view existing content.</p><p>The approval workflow is now active - you can create proposals and approve them!</p><p>You can also ask questions to the House AI in the sidebar. It will search through our documents to provide answers.</p>"
              />
            ) : (
              <Editor />
            )}
          </div>

          {/* Sidebar with proposals and AI */}
          <div className="lg:col-span-1 space-y-6">
            <QueryInterface />
            <ProposalList />
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;

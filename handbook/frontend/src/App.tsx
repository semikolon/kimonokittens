import React, { useState } from 'react';
import { ProposalList } from './components/ProposalList';
import { Editor } from './components/Editor';
import { WikiPage } from './components/WikiPage';
import { QueryInterface } from './components/QueryInterface';
import { AuthProvider, useAuth } from './context/AuthContext';
import { LoginButton } from './components/LoginButton';
import './App.css';

function AppContent() {
  const [currentView, setCurrentView] = useState<'wiki' | 'editor'>('wiki');
  const { isAuthenticated, user, logout, loading } = useAuth();

  return (
    <div className="min-h-screen">
      <header className="bg-purple-50/80 dark:bg-purple-900/80 backdrop-blur-sm border-b border-purple-200 dark:border-purple-800 sticky top-0 z-10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            <h1 className="text-xl font-semibold text-purple-900 dark:text-purple-100">
              Kimonokittens Handbook
            </h1>
            
            <div className="flex items-center gap-4">
              {/* Navigation */}
              <nav className="flex items-center gap-2">
                <button
                  onClick={() => setCurrentView('wiki')}
                  className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                    currentView === 'wiki'
                      ? 'bg-orange-500 text-white'
                      : 'text-purple-700 dark:text-purple-300 hover:bg-purple-100 dark:hover:bg-purple-800'
                  }`}
                >
                  View Content
                </button>
                <button
                  onClick={() => setCurrentView('editor')}
                  className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                    currentView === 'editor'
                      ? 'bg-orange-500 text-white'
                      : 'text-purple-700 dark:text-purple-300 hover:bg-purple-100 dark:hover:bg-purple-800'
                  }`}
                >
                  Create Proposal
                </button>
              </nav>

              {/* Authentication */}
              <div className="flex items-center gap-3 border-l border-purple-300 dark:border-purple-700 pl-4">
                {loading ? (
                  <div className="text-sm text-purple-600 dark:text-purple-400">Laddar...</div>
                ) : isAuthenticated && user ? (
                  <div className="flex items-center gap-3">
                    <div className="flex items-center gap-2">
                      <img 
                        src={user.avatarUrl} 
                        alt={user.name}
                        className="w-8 h-8 rounded-full"
                      />
                      <span className="text-sm font-medium text-purple-900 dark:text-purple-100">
                        Hej {user.name}!
                      </span>
                    </div>
                    <button
                      onClick={logout}
                      className="text-sm text-purple-600 dark:text-purple-400 hover:text-purple-800 dark:hover:text-purple-200 transition-colors"
                    >
                      Logga ut
                    </button>
                  </div>
                ) : (
                  <LoginButton className="text-sm" />
                )}
              </div>
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-12">
          {/* Main content area */}
          <div className="lg:col-span-2 bg-purple-50 dark:bg-purple-900 p-8 rounded-lg border border-purple-200 dark:border-purple-800 shadow-sm">
            {currentView === 'wiki' ? (
              <WikiPage
                title="Welcome to the Handbook"
                content="<p>This is the Kimonokittens collective handbook. Use the navigation above to create proposals or view existing content.</p><p>The approval workflow is now active - you can create proposals and approve them!</p><p>You can also ask questions to the House AI in the sidebar. It will search through our documents to provide answers.</p>"
              />
            ) : (
              <div>
                <h2 className="text-2xl font-bold mb-4 text-purple-900 dark:text-purple-100">Create a New Proposal</h2>
                {isAuthenticated ? (
                  <Editor />
                ) : (
                  <div className="text-center py-8">
                    <p className="text-purple-700 dark:text-purple-300 mb-4">
                      Du måste logga in för att skapa förslag.
                    </p>
                    <LoginButton />
                  </div>
                )}
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

function App() {
  return (
    <AuthProvider>
      <AppContent />
    </AuthProvider>
  );
}

export default App;

import React, { useState } from 'react';
import { ProposalList } from './components/ProposalList';
import { Editor } from './components/Editor';
import { WikiPage } from './components/WikiPage';
import { QueryInterface } from './components/QueryInterface';
import { AuthProvider, useAuth } from './context/AuthContext';
import LoginButton from './components/LoginButton';
import RentPanel from './components/RentPanel';
import './App.css';

function AppContent() {
  const [currentView, setCurrentView] = useState<'wiki' | 'editor'>('wiki');
  const { isAuthenticated, user, logout, loading } = useAuth();

  return (
    <div className="min-h-screen bg-slate-50">
      <header className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex justify-between items-center">
          <h1 className="text-2xl font-bold text-slate-800">Kimonokittens Handbook</h1>
          <LoginButton />
        </div>
      </header>
      
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          
          <div className="md:col-span-2 space-y-8">
            {/* Main content area */}
            <RentPanel />
            {/* You could add more primary components here, like WikiPage */}
          </div>
          
          <div className="space-y-8">
            {/* Sidebar area */}
            <QueryInterface />
            {isAuthenticated && <ProposalList />}
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

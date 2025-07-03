import React, { useState } from 'react';

export const QueryInterface: React.FC = () => {
  const [question, setQuestion] = useState('');
  const [answer, setAnswer] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!question.trim()) {
      return;
    }

    setIsLoading(true);
    setAnswer('');

    try {
      const response = await fetch('/api/handbook/query', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ question: question.trim() }),
      });

      if (response.ok) {
        const data = await response.json();
        setAnswer(data.answer || 'No answer received.');
      } else {
        const errorData = await response.json();
        setAnswer(`Error: ${errorData.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Error querying AI:', error);
      setAnswer('Error: Could not connect to the AI service.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="p-6 border rounded-lg bg-purple-50 dark:bg-purple-900 border-purple-200 dark:border-purple-800">
      <h2 className="text-xl font-bold mb-4 text-purple-900 dark:text-purple-100">Ask the House AI</h2>
      
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label htmlFor="question" className="block text-sm font-medium text-purple-800 dark:text-purple-300 mb-2">
            What would you like to know?
          </label>
          <textarea
            id="question"
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder="e.g., What's our guest policy?"
            rows={3}
            className="w-full px-3 py-2 border border-purple-300 dark:border-purple-700 bg-white dark:bg-purple-800/50 rounded-md focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent transition text-slate-800 dark:text-slate-50"
            disabled={isLoading}
          />
        </div>
        
        <button
          type="submit"
          disabled={isLoading || !question.trim()}
          className="w-full px-4 py-2 bg-orange-500 text-white font-semibold rounded-md hover:bg-orange-600 disabled:bg-orange-300 disabled:cursor-not-allowed transition-colors"
        >
          {isLoading ? 'Thinking...' : 'Ask AI'}
        </button>
      </form>

      {isLoading && (
        <div className="mt-4 p-4 bg-purple-100 dark:bg-purple-800/50 border border-purple-200 dark:border-purple-800 rounded-md">
          <div className="flex items-center">
            <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-orange-500 mr-3"></div>
            <span className="text-purple-800 dark:text-purple-300">Processing your question...</span>
          </div>
        </div>
      )}

      {answer && !isLoading && (
        <div className="mt-4 p-4 bg-purple-100 dark:bg-purple-800/50 border border-purple-200 dark:border-purple-800 rounded-md">
          <h3 className="font-semibold text-purple-900 dark:text-purple-200 mb-2">AI Response:</h3>
          <div className="text-purple-800 dark:text-purple-300 whitespace-pre-wrap">{answer}</div>
        </div>
      )}
    </div>
  );
}; 
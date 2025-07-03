import React, { useState, useEffect } from 'react';

interface Proposal {
  id: number;
  title: string;
  content: string;
  approvals: number;
  created_at: string;
}

export const ProposalList: React.FC = () => {
  const [proposals, setProposals] = useState<Proposal[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchProposals = async () => {
    try {
      const response = await fetch('/api/handbook/proposals');
      const data = await response.json();
      setProposals(data);
    } catch (error) {
      console.error('Error fetching proposals:', error);
    } finally {
      setLoading(false);
    }
  };

  const approveProposal = async (proposalId: number) => {
    try {
      const response = await fetch(`/api/handbook/proposals/${proposalId}/approve`, {
        method: 'POST',
      });
      
      if (response.ok) {
        // Refresh the proposals list
        fetchProposals();
      }
    } catch (error) {
      console.error('Error approving proposal:', error);
    }
  };

  useEffect(() => {
    fetchProposals();
  }, []);

  if (loading) {
    return <div className="p-6">Loading proposals...</div>;
  }

  return (
    <div className="p-6 border rounded-lg bg-purple-50 dark:bg-purple-900 border-purple-200 dark:border-purple-800">
      <h2 className="text-xl font-bold mb-4 text-purple-900 dark:text-purple-100">Proposals for Review</h2>
      
      {proposals.length === 0 ? (
        <p className="text-purple-700 dark:text-purple-300">No open proposals.</p>
      ) : (
        <div className="space-y-4">
          {proposals.map((proposal) => (
            <div key={proposal.id} className="border p-4 rounded-md bg-white/50 dark:bg-purple-800/50 border-purple-200 dark:border-purple-700">
              <div className="flex justify-between items-start">
                <div className="flex-1">
                  <h3 className="font-semibold text-purple-800 dark:text-purple-200">{proposal.title}</h3>
                  <p className="text-sm text-purple-600 dark:text-purple-400">Created: {proposal.created_at}</p>
                  <div className="mt-2 text-sm text-slate-700 dark:text-slate-300 prose prose-sm" 
                       dangerouslySetInnerHTML={{ __html: proposal.content }} />
                </div>
                <div className="ml-4 text-center flex-shrink-0">
                  <div className="text-lg font-bold text-orange-600 dark:text-orange-500">
                    {proposal.approvals} approvals
                  </div>
                  <button
                    onClick={() => approveProposal(proposal.id)}
                    className="mt-2 px-3 py-1 bg-orange-500 text-white text-sm font-semibold rounded-md hover:bg-orange-600 transition-colors"
                  >
                    Approve
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}; 
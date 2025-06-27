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
    return <div className="p-4">Loading proposals...</div>;
  }

  return (
    <div className="p-4 border rounded-lg bg-gray-50">
      <h2 className="text-xl font-bold mb-4">Proposals</h2>
      
      {proposals.length === 0 ? (
        <p className="text-gray-600">No proposals yet.</p>
      ) : (
        <div className="space-y-3">
          {proposals.map((proposal) => (
            <div key={proposal.id} className="border p-3 rounded bg-white">
              <div className="flex justify-between items-start">
                <div className="flex-1">
                  <h3 className="font-semibold">{proposal.title}</h3>
                  <p className="text-sm text-gray-600">Created: {proposal.created_at}</p>
                  <div className="mt-2 text-sm text-gray-800 prose prose-sm" 
                       dangerouslySetInnerHTML={{ __html: proposal.content }} />
                </div>
                <div className="ml-4 text-center">
                  <div className="text-lg font-bold text-green-600">
                    {proposal.approvals} approvals
                  </div>
                  <button
                    onClick={() => approveProposal(proposal.id)}
                    className="mt-2 px-3 py-1 bg-green-500 text-white rounded hover:bg-green-600"
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
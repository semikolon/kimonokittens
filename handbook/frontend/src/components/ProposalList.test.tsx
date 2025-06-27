import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ProposalList } from './ProposalList';

// Mock fetch
global.fetch = vi.fn();

describe('ProposalList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows loading state initially', () => {
    (fetch as any).mockResolvedValueOnce({
      ok: true,
      json: async () => []
    });

    render(<ProposalList />);
    expect(screen.getByText('Loading proposals...')).toBeInTheDocument();
  });

  it('shows empty state when no proposals exist', async () => {
    (fetch as any).mockResolvedValueOnce({
      ok: true,
      json: async () => []
    });

    render(<ProposalList />);
    
    await waitFor(() => {
      expect(screen.getByText('No proposals yet.')).toBeInTheDocument();
    });
  });

  it('displays proposals when they exist', async () => {
    const mockProposals = [
      {
        id: 1,
        title: 'Test Proposal',
        content: '<p>Test content</p>',
        approvals: 2,
        created_at: '2025-01-01 12:00:00'
      }
    ];

    (fetch as any).mockResolvedValueOnce({
      ok: true,
      json: async () => mockProposals
    });

    render(<ProposalList />);
    
    await waitFor(() => {
      expect(screen.getByText('Test Proposal')).toBeInTheDocument();
      expect(screen.getByText('2 approvals')).toBeInTheDocument();
      expect(screen.getByText('Created: 2025-01-01 12:00:00')).toBeInTheDocument();
    });
  });

  it('handles approval button click', async () => {
    const user = userEvent.setup();
    const mockProposals = [
      {
        id: 1,
        title: 'Test Proposal',
        content: '<p>Test content</p>',
        approvals: 0,
        created_at: '2025-01-01 12:00:00'
      }
    ];

    // First fetch for initial load
    (fetch as any).mockResolvedValueOnce({
      ok: true,
      json: async () => mockProposals
    });

    render(<ProposalList />);
    
    await waitFor(() => {
      expect(screen.getByText('Test Proposal')).toBeInTheDocument();
    });

    // Mock approval response
    (fetch as any).mockResolvedValueOnce({
      ok: true
    });

    // Mock refresh response with updated approvals
    (fetch as any).mockResolvedValueOnce({
      ok: true,
      json: async () => [{ ...mockProposals[0], approvals: 1 }]
    });

    const approveButton = screen.getByText('Approve');
    await user.click(approveButton);

    await waitFor(() => {
      expect(fetch).toHaveBeenCalledWith('/api/handbook/proposals/1/approve', {
        method: 'POST'
      });
    });
  });

  it('handles fetch errors gracefully', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
    
    (fetch as any).mockRejectedValueOnce(new Error('Network error'));

    render(<ProposalList />);
    
    await waitFor(() => {
      // Component should still render, just with no proposals
      expect(screen.queryByText('Loading proposals...')).not.toBeInTheDocument();
    });

    expect(consoleError).toHaveBeenCalledWith('Error fetching proposals:', expect.any(Error));
    
    consoleError.mockRestore();
  });
}); 
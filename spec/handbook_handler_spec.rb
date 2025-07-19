require 'rspec'
require_relative '../handlers/handbook_handler'
require_relative 'support/api_test_helpers'

RSpec.describe HandbookHandler do
  include ApiTestHelpers

  let(:handler) { HandbookHandler.new }

  # Mock the Git repository to avoid file system interactions
  let(:mock_repo) { double('Rugged::Repository') }
  let(:mock_branches) { double('Rugged::BranchCollection') }
  
  before do
    allow(HandbookHandler).to receive(:repo).and_return(mock_repo)
    allow(mock_repo).to receive(:branches).and_return(mock_branches)
  end

  describe 'GET /api/handbook/proposals' do
    it 'returns an empty list when there are no proposal branches' do
      allow(mock_branches).to receive(:each).and_return([])
      
      status, _, body = get_json(handler, '/api/handbook/proposals')
      
      expect(status).to eq(200)
      expect(body).to eq([])
    end
  end

  describe 'POST /api/handbook/proposals' do
    let(:main_branch) { double('Rugged::Branch', target: double('Rugged::Commit', tree: double('Rugged::Tree'))) }
    let(:mock_index) { double('Rugged::Index') }

    before do
      allow(mock_branches).to receive(:[]).with('master').and_return(main_branch)
      allow(mock_repo).to receive(:index).and_return(mock_index)
      allow(mock_index).to receive(:read_tree)
      allow(mock_repo).to receive(:write).and_return('blob_oid')
      allow(mock_index).to receive(:add)
      allow(mock_index).to receive(:write_tree).and_return('tree_oid')
      allow(Rugged::Commit).to receive(:create).and_return('commit_oid')
      allow(mock_repo).to receive(:create_branch)
    end

    it 'creates a new proposal branch successfully' do
      payload = {
        content: '# New Idea',
        page_path: 'handbook/docs/new-idea.md',
        author: 'test-user'
      }
      status, _, body = post_json(handler, '/api/handbook/proposals', payload)

      expect(status).to eq(200)
      expect(body[:id]).to include('proposals/test-user/')
      expect(body[:author]).to eq('test-user')
      expect(body[:approvals]).to eq(0)
    end
  end
  
  describe 'POST /api/handbook/proposals/:id/approve' do
    let(:proposal_branch_name) { 'proposals/test-user/12345-test' }
    let(:mock_commit) { double('Rugged::Commit', tree: mock_tree) }
    let(:mock_tree) { double('Rugged::Tree') }
    let(:proposal_branch) { double('Rugged::Branch', target: mock_commit) }
    let(:mock_index) { double('Rugged::Index') }
    let(:new_mock_tree) { double('Rugged::Tree') }

    before do
      allow(mock_branches).to receive(:[]).with(proposal_branch_name).and_return(proposal_branch)
      # Mock the tree to not have any existing approvals
      allow(mock_tree).to receive(:any?).and_return(false) # Not already approved
      allow(mock_repo).to receive(:index).and_return(mock_index)
      allow(mock_index).to receive(:read_tree)
      allow(mock_repo).to receive(:write).and_return('blob_oid')
      allow(mock_index).to receive(:add)
      allow(mock_index).to receive(:write_tree).and_return('tree_oid')
      allow(Rugged::Commit).to receive(:create).and_return('commit_oid')
      allow(mock_repo).to receive(:references).and_return(double.as_null_object)
      # Mock the new tree after approval is added - this is the key fix
      allow(mock_repo).to receive(:lookup).with('tree_oid').and_return(new_mock_tree)
      allow(new_mock_tree).to receive(:each).and_yield({ name: '.approval.approver1' })
    end
    
    it 'approves a proposal successfully' do
       payload = { approver: 'approver1' }
       status, _, body = post_json(handler, "/api/handbook/proposals/#{proposal_branch_name}/approve", payload)
       
       expect(status).to eq(200)
       expect(body[:approvals]).to eq(1)
       expect(body[:approvers]).to eq(['approver1'])
    end
  end

  describe 'GET /api/handbook/pages/:slug' do
    it 'returns mock page content' do
      status, _, body = get_json(handler, '/api/handbook/pages/rules')

      expect(status).to eq(200)
      expect(body[:title]).to eq('Mock Page: Rules')
      expect(body[:content]).to include('<h1>Rules</h1>')
    end
  end

  describe 'Unknown routes' do
    it 'returns 404 for unknown paths' do
      status, _, body = get_json(handler, '/api/handbook/unknown')

      expect(status).to eq(404)
      expect(body[:error]).to eq('Not Found')
    end
  end
end 
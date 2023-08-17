require 'rspec'
require 'rspec/mocks'
require 'bank_buster'

# The tests will now include some typical happy path scenarios

describe BankBuster do
  before(:each) do
    @ferrum = double('ferrum')
    allow(Ferrum).to receive(:new).and_return(@ferrum)
    @bank_buster = BankBuster.new()
  end

  it 'should raise login error if login process fails' do
    expect {@bank_buster.input_login_and_get_qr_code}.to raise_error(LoginError)
  end

  it 'should raise file retrieval error if download fails' do
    expect {@bank_buster.download_file(id: "123456", headers: { 'Auth-Token' => 'fake_token' })}.to raise_error(FileRetrievalError)
  end

  # simulating QR code scanned and authenticated in bank app
  it 'should successfully complete the login process once QR is scanned' do
    allow(@bank_buster).to receive(:at_css).with().and_return(nil)
    expect(@bank_buster.at_css("p[data-cy='verify-yourself']")).to receive(:text).and_return(ENV['BANK_ID_AUTH_TEXT'])
    expect(@bank_buster.login_process).to be_truthy
  end

  # mocking the scenario where files are successfully downloaded
  it 'should successfully download all payment files' do
    allow(@bank_buster).to receive(:download_file).with().and_return(nil)
    expect(@bank_buster.download_all_payment_files.count).to eq(0)
  end

  # simulating retrieval of files after successful login
  it 'should successfully retrieve files after log in' do
    allow(@bank_buster).to receive(:download_all_payment_files).and_return(["file1.xml", "file2.xml"])
    expect(@bank_buster.retrieve_files { |result| result[:filenames] }).to eq(["file1.xml", "file2.xml"])
  end
end

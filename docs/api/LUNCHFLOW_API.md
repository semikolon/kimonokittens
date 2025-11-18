# Lunch Flow API Documentation

**Version:** v1
**Base URL:** `https://www.lunchflow.app/api/v1`
**Authentication:** API Key (via custom header)
**Status:** Production (VERIFIED Nov 15, 2025)

**⚠️ Ruby SSL Note:** Ruby's `Net::HTTP` may encounter SSL certificate CRL verification errors with this domain. For production use, add `verify_mode: OpenSSL::SSL::VERIFY_NONE` to the HTTP connection options. This is a known issue with certificate revocation list (CRL) checking.

## Overview

Lunch Flow is a bank aggregation service that connects to thousands of banks globally via multiple open banking providers (GoCardless, Finicity, MX, Finverse, and others). The API enables programmatic access to bank account data, balances, and transaction history.

**Key Features:**
- Access to global bank connections through open banking standards
- Real-time account balances and transaction data
- Daily automatic synchronization
- Support for multiple currencies
- Deduplication and data normalization

**Pricing:**
- All plans include full API access
- Entry-level: £2.50/month (billed annually at £29.99/year)
- 7-day free trial available
- Generous rate limits included (specific limits not publicly documented)

## Getting Your API Key

1. Sign up at https://www.lunchflow.app/signin/signup
2. Navigate to your account settings or developer section
3. Generate an API key for programmatic access
4. Store the API key securely (it grants full access to your connected bank data)

**Security Note:** API keys are encrypted at rest by Lunch Flow and should be treated as sensitive credentials.

## Authentication

Lunch Flow uses **API key authentication** via a custom HTTP header (not OAuth2 Bearer tokens).

### Authentication Header

```http
x-api-key: YOUR_API_KEY_HERE
Content-Type: application/json
```

### Example Request

```bash
curl -X GET https://www.lunchflow.app/api/v1/accounts \
  -H "x-api-key: YOUR_API_KEY_HERE" \
  -H "Content-Type: application/json"
```

### Authentication Errors

| Status Code | Description |
|------------|-------------|
| 401 | Invalid or missing API key |
| 403 | API key valid but lacks permission for requested resource |

## API Endpoints

### Health Check / Test Connection

**Purpose:** Validate API credentials and connectivity

```http
GET /accounts
```

**Authentication:** Required  
**Response:** 200 OK indicates successful connection

**Use Case:** Before making other API calls, verify your API key works by requesting the accounts endpoint.

---

### Get Accounts

Retrieve all bank accounts connected to your Lunch Flow account.

```http
GET /accounts
```

**Authentication:** Required

**Response Schema:**

```json
{
  "accounts": [
    {
      "id": 12345,
      "name": "Main Checking",
      "institution_name": "Example Bank"
    },
    {
      "id": 67890,
      "name": "Savings Account",
      "institution_name": "Another Bank"
    }
  ]
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `accounts` | array | List of connected bank accounts |
| `accounts[].id` | number | Unique account identifier (used in transaction queries) |
| `accounts[].name` | string | Account name/nickname |
| `accounts[].institution_name` | string | Name of the financial institution |

**Example Request (JavaScript):**

```javascript
const response = await fetch('https://www.lunchflow.app/api/v1/accounts', {
  headers: {
    'x-api-key': 'YOUR_API_KEY_HERE',
    'Content-Type': 'application/json'
  }
});

const data = await response.json();
console.log('Connected accounts:', data.accounts);
```

**Example Request (Ruby):**

```ruby
require 'net/http'
require 'json'

uri = URI('https://www.lunchflow.app/api/v1/accounts')
request = Net::HTTP::Get.new(uri)
request['x-api-key'] = 'YOUR_API_KEY_HERE'
request['Content-Type'] = 'application/json'

response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  http.request(request)
end

accounts = JSON.parse(response.body)['accounts']
puts "Found #{accounts.length} accounts"
```

**Error Handling:**

- If the response structure is unexpected (missing `accounts` array), client implementations should gracefully return an empty array
- Non-200 status codes indicate authentication or server issues

---

### Get Transactions

Retrieve transaction history for a specific account.

```http
GET /accounts/{accountId}/transactions
```

**Path Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `accountId` | number | Yes | Account ID from the accounts endpoint |

**Authentication:** Required

**Query Parameters:**

⚠️ **Note:** The public implementation does not show query parameters for date filtering. The API appears to return all available transactions, with filtering done client-side.

**Response Schema:**

```json
{
  "transactions": [
    {
      "id": "txn_abc123",
      "accountId": 12345,
      "date": "2025-11-14",
      "amount": -45.67,
      "currency": "GBP",
      "merchant": "Coffee Shop",
      "description": "COFFEE SHOP LONDON"
    },
    {
      "id": "txn_def456",
      "accountId": 12345,
      "date": "2025-11-13",
      "amount": -120.00,
      "currency": "GBP",
      "merchant": "Grocery Store",
      "description": "GROCERY STORE PURCHASE"
    }
  ]
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `transactions` | array | List of transactions for the account |
| `transactions[].id` | string | Unique transaction identifier |
| `transactions[].accountId` | number | Associated account ID |
| `transactions[].date` | string | Transaction date (ISO 8601 format: YYYY-MM-DD) |
| `transactions[].amount` | number | Transaction amount (negative = debit, positive = credit) |
| `transactions[].currency` | string | ISO 4217 currency code (e.g., GBP, USD, EUR, SEK) |
| `transactions[].merchant` | string | Merchant/counterparty name (normalized by Lunch Flow) |
| `transactions[].description` | string | Original transaction description from bank |

**Example Request (JavaScript):**

```javascript
const accountId = 12345;
const response = await fetch(
  `https://www.lunchflow.app/api/v1/accounts/${accountId}/transactions`,
  {
    headers: {
      'x-api-key': 'YOUR_API_KEY_HERE',
      'Content-Type': 'application/json'
    }
  }
);

const data = await response.json();
console.log(`Found ${data.transactions.length} transactions`);

// Client-side date filtering (if needed)
const startDate = '2025-11-01';
const filtered = data.transactions.filter(t => t.date >= startDate);
```

**Example Request (Ruby):**

```ruby
require 'net/http'
require 'json'
require 'date'

account_id = 12345
uri = URI("https://www.lunchflow.app/api/v1/accounts/#{account_id}/transactions")
request = Net::HTTP::Get.new(uri)
request['x-api-key'] = 'YOUR_API_KEY_HERE'
request['Content-Type'] = 'application/json'

response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  http.request(request)
end

transactions = JSON.parse(response.body)['transactions']

# Client-side date filtering
start_date = Date.parse('2025-11-01')
recent_transactions = transactions.select { |t| Date.parse(t['date']) >= start_date }

puts "Found #{recent_transactions.length} transactions since #{start_date}"
```

**Date Filtering Best Practice:**

Since the API returns all transactions, implement client-side filtering:

```javascript
function filterByDateRange(transactions, startDate, endDate = null) {
  return transactions.filter(t => {
    const txnDate = t.date;
    if (endDate) {
      return txnDate >= startDate && txnDate <= endDate;
    }
    return txnDate >= startDate;
  });
}

// Usage
const recentTransactions = filterByDateRange(
  data.transactions,
  '2025-11-01',
  '2025-11-15'
);
```

**Error Handling:**

- If the response structure is unexpected (missing `transactions` array), client implementations should gracefully return an empty array
- Non-200 status codes indicate authentication or server issues

---

## Pagination

**Status:** Not explicitly documented in public implementations.

The current client implementations fetch all transactions for an account in a single request without pagination parameters. This suggests either:
- The API returns all available transactions (likely capped by Lunch Flow's retention policy)
- Pagination exists but isn't exposed in the open-source client
- Transaction volumes are expected to be manageable within a single response

**Recommendation:** Start with the assumption that all transactions are returned. Monitor response sizes and implement client-side chunking if needed.

---

## Rate Limiting

**Policy:** "Generous rate limits" mentioned in marketing materials, but specific numbers are not publicly documented.

**Best Practices:**

1. **Implement Retry Logic with Exponential Backoff:**

```javascript
async function fetchWithRetry(url, options, maxRetries = 3) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const response = await fetch(url, options);
      
      if (response.status === 429) {
        // Rate limited - wait and retry
        const delay = Math.pow(2, attempt) * 1000; // 1s, 2s, 4s
        await new Promise(resolve => setTimeout(resolve, delay));
        continue;
      }
      
      return response;
    } catch (error) {
      if (attempt === maxRetries - 1) throw error;
      await new Promise(resolve => setTimeout(resolve, Math.pow(2, attempt) * 1000));
    }
  }
}
```

2. **Handle Network Errors:**

Retry on these error conditions:
- `ECONNRESET` - Connection reset
- `ETIMEDOUT` - Request timeout
- `ENOTFOUND` - DNS resolution failure
- `ECONNABORTED` - Connection aborted
- HTTP 5xx server errors (status >= 500)

3. **Timeout Configuration:**

Set reasonable timeouts (recommended: 60 seconds) to handle slow responses:

```javascript
const controller = new AbortController();
const timeoutId = setTimeout(() => controller.abort(), 60000);

const response = await fetch(url, {
  signal: controller.signal,
  headers: { 'x-api-key': apiKey }
});

clearTimeout(timeoutId);
```

**Expected Rate Limit Response:**

```http
HTTP/1.1 429 Too Many Requests
Content-Type: application/json

{
  "error": "Rate limit exceeded",
  "retry_after": 60
}
```

---

## Error Handling

### HTTP Status Codes

| Status Code | Meaning | Action |
|------------|---------|--------|
| 200 | Success | Process response data |
| 400 | Bad Request | Check request parameters and payload |
| 401 | Unauthorized | Verify API key is correct and active |
| 403 | Forbidden | API key lacks permission for this resource |
| 404 | Not Found | Endpoint or resource doesn't exist (check account ID) |
| 429 | Too Many Requests | Implement exponential backoff and retry |
| 500 | Internal Server Error | Retry with exponential backoff (server issue) |
| 502 | Bad Gateway | Retry with exponential backoff (upstream provider issue) |
| 503 | Service Unavailable | Retry with exponential backoff (temporary outage) |

### Error Response Format

**Assumption:** Based on common REST API patterns. Actual format may vary.

```json
{
  "error": "Invalid account ID",
  "message": "Account 99999 not found or not accessible with this API key",
  "code": "ACCOUNT_NOT_FOUND"
}
```

### Robust Error Handling Example (Ruby)

```ruby
class LunchFlowClient
  MAX_RETRIES = 3
  TIMEOUT_SECONDS = 60
  
  def get_transactions(account_id)
    attempt = 0
    
    begin
      uri = URI("https://www.lunchflow.app/api/v1/accounts/#{account_id}/transactions")
      request = Net::HTTP::Get.new(uri)
      request['x-api-key'] = @api_key
      request['Content-Type'] = 'application/json'
      
      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: true,
        read_timeout: TIMEOUT_SECONDS,
        open_timeout: TIMEOUT_SECONDS
      ) do |http|
        http.request(request)
      end
      
      case response.code.to_i
      when 200
        data = JSON.parse(response.body)
        return data['transactions'] || []
      when 429
        if attempt < MAX_RETRIES
          delay = 2 ** attempt
          sleep(delay)
          attempt += 1
          retry
        end
        raise "Rate limit exceeded after #{MAX_RETRIES} retries"
      when 401, 403
        raise "Authentication failed: #{response.body}"
      when 404
        raise "Account #{account_id} not found"
      when 500..599
        if attempt < MAX_RETRIES
          delay = 2 ** attempt
          sleep(delay)
          attempt += 1
          retry
        end
        raise "Server error after #{MAX_RETRIES} retries"
      else
        raise "Unexpected status #{response.code}: #{response.body}"
      end
      
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET
      if attempt < MAX_RETRIES
        delay = 2 ** attempt
        sleep(delay)
        attempt += 1
        retry
      end
      raise "Network error after #{MAX_RETRIES} retries"
    end
  end
end
```

---

## Data Freshness & Synchronization

**Automatic Sync:** Lunch Flow automatically updates transactions and balances daily from connected banks.

**Update Frequency:**
- **Transactions:** Once per day (overnight sync)
- **Balances:** Once per day (overnight sync)

**Implementation Note:** For real-time balance/transaction tracking, consider polling the API once daily after the sync window (recommend: early morning UTC).

---

## Webhooks

**Status:** Not documented in public implementations or marketing materials.

**Current State:** No evidence of webhook support for real-time transaction notifications.

**Workaround:** Implement polling strategy:
1. Poll `/accounts/{accountId}/transactions` once daily
2. Compare with locally stored transactions
3. Identify new transactions by ID
4. Process new transactions

**Example Polling Strategy (Ruby):**

```ruby
class TransactionPoller
  def initialize(api_client, account_id, storage)
    @api_client = api_client
    @account_id = account_id
    @storage = storage  # Your database/storage layer
  end
  
  def sync_transactions
    remote_transactions = @api_client.get_transactions(@account_id)
    local_ids = @storage.get_transaction_ids(@account_id)
    
    new_transactions = remote_transactions.reject do |txn|
      local_ids.include?(txn['id'])
    end
    
    new_transactions.each do |txn|
      @storage.save_transaction(txn)
      yield(txn) if block_given?  # Callback for processing
    end
    
    puts "Synced #{new_transactions.length} new transactions"
    new_transactions
  end
end

# Usage with scheduled job (e.g., cron)
poller = TransactionPoller.new(client, account_id, storage)
poller.sync_transactions do |transaction|
  # Process new transaction
  RentPaymentDetector.check(transaction)
end
```

---

## Testing & Sandbox Environment

**Status:** Not publicly documented.

**Assumption:** No separate sandbox/test environment is available. Testing must be done carefully against production API with real bank connections.

**Testing Best Practices:**

1. **Use a dedicated test account:**
   - Create a separate Lunch Flow account for development
   - Connect a low-activity bank account
   - Never test against your primary personal/business accounts

2. **Implement dry-run mode:**

```ruby
class LunchFlowIntegration
  def initialize(api_key, dry_run: false)
    @api_key = api_key
    @dry_run = dry_run
  end
  
  def process_transaction(transaction)
    if @dry_run
      puts "[DRY RUN] Would process: #{transaction.inspect}"
      return
    end
    
    # Actual processing logic
    save_to_database(transaction)
  end
end
```

3. **Log all API interactions:**

```ruby
require 'logger'

logger = Logger.new('lunchflow_api.log')
logger.level = Logger::DEBUG

# Log before each API call
logger.info("Fetching transactions for account #{account_id}")
response = client.get_transactions(account_id)
logger.debug("Response: #{response.inspect}")
```

---

## Integration Examples

### Complete Ruby Client Implementation

```ruby
require 'net/http'
require 'json'
require 'logger'

class LunchFlowClient
  BASE_URL = 'https://www.lunchflow.app/api/v1'
  TIMEOUT = 60
  MAX_RETRIES = 3
  
  def initialize(api_key, logger: Logger.new(STDOUT))
    @api_key = api_key
    @logger = logger
  end
  
  # Test API connectivity
  def health_check
    @logger.info('Testing Lunch Flow API connection...')
    response = get('/accounts')
    response.code.to_i == 200
  rescue => e
    @logger.error("Health check failed: #{e.message}")
    false
  end
  
  # Get all connected accounts
  def get_accounts
    @logger.info('Fetching accounts...')
    response = get('/accounts')
    data = parse_response(response)
    accounts = data['accounts'] || []
    @logger.info("Found #{accounts.length} accounts")
    accounts
  end
  
  # Get transactions for specific account
  def get_transactions(account_id, start_date: nil)
    @logger.info("Fetching transactions for account #{account_id}...")
    response = get("/accounts/#{account_id}/transactions")
    data = parse_response(response)
    transactions = data['transactions'] || []
    
    # Client-side date filtering
    if start_date
      transactions.select! { |t| t['date'] >= start_date }
      @logger.info("Filtered to #{transactions.length} transactions since #{start_date}")
    else
      @logger.info("Found #{transactions.length} transactions")
    end
    
    transactions
  end
  
  private
  
  def get(path)
    attempt = 0
    
    begin
      uri = URI("#{BASE_URL}#{path}")
      request = Net::HTTP::Get.new(uri)
      request['x-api-key'] = @api_key
      request['Content-Type'] = 'application/json'
      
      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: true,
        read_timeout: TIMEOUT,
        open_timeout: TIMEOUT
      ) do |http|
        http.request(request)
      end
      
      handle_response(response, attempt)
      
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET => e
      if attempt < MAX_RETRIES
        delay = 2 ** attempt
        @logger.warn("Network error, retrying in #{delay}s... (#{e.class})")
        sleep(delay)
        attempt += 1
        retry
      end
      raise "Network error after #{MAX_RETRIES} retries: #{e.message}"
    end
  end
  
  def handle_response(response, attempt)
    case response.code.to_i
    when 200
      response
    when 429
      if attempt < MAX_RETRIES
        delay = 2 ** attempt
        @logger.warn("Rate limited, retrying in #{delay}s...")
        sleep(delay)
        raise 'retry'
      end
      raise 'Rate limit exceeded'
    when 401, 403
      raise "Authentication failed: #{response.body}"
    when 404
      raise "Resource not found: #{response.body}"
    when 500..599
      if attempt < MAX_RETRIES
        delay = 2 ** attempt
        @logger.warn("Server error, retrying in #{delay}s...")
        sleep(delay)
        raise 'retry'
      end
      raise "Server error after retries: #{response.body}"
    else
      raise "Unexpected status #{response.code}: #{response.body}"
    end
  end
  
  def parse_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    @logger.error("Failed to parse JSON response: #{e.message}")
    {}
  end
end

# Usage example
if __FILE__ == $0
  api_key = ENV['LUNCHFLOW_API_KEY']
  client = LunchFlowClient.new(api_key)
  
  # Test connection
  if client.health_check
    puts "✓ Connected to Lunch Flow API"
  else
    puts "✗ Connection failed"
    exit 1
  end
  
  # Get accounts
  accounts = client.get_accounts
  accounts.each do |account|
    puts "\nAccount: #{account['name']} (#{account['institution_name']})"
    
    # Get recent transactions (last 30 days)
    start_date = (Date.today - 30).to_s
    transactions = client.get_transactions(account['id'], start_date: start_date)
    
    puts "  Recent transactions: #{transactions.length}"
    transactions.first(5).each do |txn|
      puts "    #{txn['date']} | #{txn['amount']} #{txn['currency']} | #{txn['merchant']}"
    end
  end
end
```

### JavaScript/TypeScript Client Implementation

```typescript
interface LunchFlowAccount {
  id: number;
  name: string;
  institution_name: string;
}

interface LunchFlowTransaction {
  id: string;
  accountId: number;
  date: string;
  amount: number;
  currency: string;
  merchant: string;
  description: string;
}

class LunchFlowClient {
  private apiKey: string;
  private baseUrl = 'https://www.lunchflow.app/api/v1';
  private timeout = 60000;
  private maxRetries = 3;
  
  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }
  
  async healthCheck(): Promise<boolean> {
    try {
      const response = await this.get('/accounts');
      return response.ok;
    } catch {
      return false;
    }
  }
  
  async getAccounts(): Promise<LunchFlowAccount[]> {
    const response = await this.get('/accounts');
    const data = await response.json();
    return data.accounts || [];
  }
  
  async getTransactions(
    accountId: number,
    startDate?: string
  ): Promise<LunchFlowTransaction[]> {
    const response = await this.get(`/accounts/${accountId}/transactions`);
    const data = await response.json();
    let transactions = data.transactions || [];
    
    if (startDate) {
      transactions = transactions.filter(t => t.date >= startDate);
    }
    
    return transactions;
  }
  
  private async get(path: string, attempt = 0): Promise<Response> {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), this.timeout);
      
      const response = await fetch(`${this.baseUrl}${path}`, {
        method: 'GET',
        headers: {
          'x-api-key': this.apiKey,
          'Content-Type': 'application/json'
        },
        signal: controller.signal
      });
      
      clearTimeout(timeoutId);
      
      if (response.status === 429 && attempt < this.maxRetries) {
        const delay = Math.pow(2, attempt) * 1000;
        await this.sleep(delay);
        return this.get(path, attempt + 1);
      }
      
      if (response.status >= 500 && attempt < this.maxRetries) {
        const delay = Math.pow(2, attempt) * 1000;
        await this.sleep(delay);
        return this.get(path, attempt + 1);
      }
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${await response.text()}`);
      }
      
      return response;
      
    } catch (error) {
      if (attempt < this.maxRetries && this.isRetriableError(error)) {
        const delay = Math.pow(2, attempt) * 1000;
        await this.sleep(delay);
        return this.get(path, attempt + 1);
      }
      throw error;
    }
  }
  
  private isRetriableError(error: any): boolean {
    const retriableCodes = ['ECONNRESET', 'ETIMEDOUT', 'ENOTFOUND', 'ECONNABORTED'];
    return retriableCodes.includes(error.code) || error.name === 'AbortError';
  }
  
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// Usage example
async function main() {
  const apiKey = process.env.LUNCHFLOW_API_KEY!;
  const client = new LunchFlowClient(apiKey);
  
  // Test connection
  if (await client.healthCheck()) {
    console.log('✓ Connected to Lunch Flow API');
  } else {
    console.log('✗ Connection failed');
    process.exit(1);
  }
  
  // Get accounts
  const accounts = await client.getAccounts();
  console.log(`Found ${accounts.length} accounts`);
  
  for (const account of accounts) {
    console.log(`\nAccount: ${account.name} (${account.institution_name})`);
    
    // Get last 30 days of transactions
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
      .toISOString()
      .split('T')[0];
    
    const transactions = await client.getTransactions(account.id, thirtyDaysAgo);
    console.log(`  Recent transactions: ${transactions.length}`);
    
    transactions.slice(0, 5).forEach(txn => {
      console.log(`    ${txn.date} | ${txn.amount} ${txn.currency} | ${txn.merchant}`);
    });
  }
}
```

---

## Use Cases for Kimonokittens Rent System

### Rent Payment Detection

**Scenario:** Automatically detect when tenants pay rent via bank transfer.

**Implementation Strategy:**

1. **Daily sync cron job** fetches new transactions
2. **Pattern matching** identifies rent payments:
   - Amount matches expected rent
   - Date near expected payment date (27th of month)
   - Description contains tenant name or apartment reference
3. **Update RentLedger** when payment detected
4. **WebSocket notification** to dashboard

**Example Detection Logic:**

```ruby
class RentPaymentDetector
  RENT_AMOUNT = 7045  # Expected rent per person
  PAYMENT_WINDOW_DAYS = 5  # Days before/after 27th
  
  def self.check_transaction(transaction, tenant)
    # Check amount
    return false unless (transaction['amount'].abs - RENT_AMOUNT).abs < 1.0
    
    # Check date (within 5 days of 27th)
    payment_date = Date.parse(transaction['date'])
    target_date = Date.new(payment_date.year, payment_date.month, 27)
    return false unless (payment_date - target_date).abs <= PAYMENT_WINDOW_DAYS
    
    # Check description for tenant name
    description = transaction['description'].downcase
    tenant_name = tenant['name'].downcase
    return false unless description.include?(tenant_name) || 
                        description.include?(tenant['apartment'])
    
    true
  end
  
  def self.process_payment(transaction, tenant)
    RentLedger.record_payment(
      tenant_id: tenant['id'],
      amount: transaction['amount'].abs,
      payment_date: transaction['date'],
      transaction_id: transaction['id'],
      source: 'lunch_flow_auto'
    )
    
    WebSocketBroadcaster.notify('rent_payment_received', {
      tenant: tenant['name'],
      amount: transaction['amount'].abs
    })
  end
end
```

### Account Balance Monitoring

**Scenario:** Check if landlord account has sufficient balance for utilities payments.

```ruby
class BalanceMonitor
  MIN_BALANCE_THRESHOLD = 10000  # SEK
  
  def self.check_balances(client)
    accounts = client.get_accounts
    landlord_account = accounts.find { |a| a['name'].include?('Landlord') }
    
    if landlord_account
      # Note: Balance endpoint not documented, may need to sum transactions
      recent = client.get_transactions(landlord_account['id'], start_date: '2025-01-01')
      balance = recent.sum { |t| t['amount'] }
      
      if balance < MIN_BALANCE_THRESHOLD
        send_low_balance_alert(balance)
      end
    end
  end
end
```

---

## API Gotchas & Best Practices

### 1. **Graceful Degradation on Missing Fields**

The API response structure should be validated. Always handle missing `accounts` or `transactions` arrays:

```ruby
accounts = data['accounts'] || []
transactions = data['transactions'] || []
```

### 2. **Transaction Amount Sign Convention**

- **Negative amounts** = debits (money leaving account)
- **Positive amounts** = credits (money entering account)

For rent payments received, expect **positive** amounts.

### 3. **Date Filtering is Client-Side**

Since the API doesn't support server-side date filtering:
- Fetch all transactions
- Filter locally by date
- Cache results to minimize API calls
- Store last sync timestamp to avoid processing old data

### 4. **Merchant vs Description Field**

- **`merchant`**: Normalized counterparty name (e.g., "Coffee Shop")
- **`description`**: Raw bank description (e.g., "COFFEE SHOP LONDON 14 NOV")

Use `description` for tenant name matching (bank reference text), `merchant` for categorization.

### 5. **Currency Awareness**

All transactions include a `currency` field. If you handle multiple currencies:

```ruby
def convert_to_base_currency(amount, currency)
  return amount if currency == 'SEK'
  
  # Fetch exchange rate or use cached rates
  rate = ExchangeRateService.get_rate(currency, 'SEK')
  amount * rate
end
```

### 6. **Transaction ID Uniqueness**

Transaction IDs are globally unique strings. Use them for deduplication:

```ruby
existing_ids = Set.new(RentLedger.pluck(:transaction_id))
new_transactions = transactions.reject { |t| existing_ids.include?(t['id']) }
```

### 7. **No Real-Time Updates**

Since updates happen once daily:
- Don't poll more frequently than daily
- Set expectations with users (not real-time)
- Run sync jobs during low-traffic hours (e.g., 3 AM)

---

## Comparison with Lunch Money API

Since Lunch Flow integrates with Lunch Money, here's how they differ:

| Feature | Lunch Flow | Lunch Money |
|---------|-----------|-------------|
| **Purpose** | Bank aggregation via open banking | Personal finance app with budgeting |
| **Auth** | `x-api-key` header | `Bearer` token |
| **Base URL** | `www.lunchflow.app/api/v1` | `dev.lunchmoney.app` |
| **Transactions** | Direct from banks | From Plaid, imports, manual entry |
| **Categories** | Not mentioned | Full categorization system |
| **Budgets** | No | Yes |
| **Tags** | No | Yes |
| **Recurring** | No | Yes |

**When to use Lunch Flow:** You need direct bank transaction access for European/UK banks via open banking.

**When to use Lunch Money:** You need budgeting features, categorization, and manual transaction management.

---

## Community Resources

### Open Source Projects

- **actual-flow** ([GitHub](https://github.com/lunchflow/actual-flow)): CLI tool for syncing Lunch Flow → Actual Budget
  - Production-grade TypeScript implementation
  - Demonstrates retry logic, error handling, deduplication
  - Good reference for API integration patterns

### Getting Help

- **Feedback Portal:** https://feedback.lunchflow.app
- **Help Center:** https://help.lunchflow.app
- **Email Support:** hello@lunchflow.app (inferred from domain)

---

## Future API Enhancements (Speculative)

Based on common API evolution patterns, these features may be added:

1. **Server-side date filtering** for transactions endpoint
2. **Pagination** with `limit` and `offset` or cursor-based pagination
3. **Webhooks** for real-time transaction notifications
4. **Account balance** endpoint (currently inferred from transaction sums)
5. **Transaction search/filtering** by merchant, amount range, description
6. **Batch operations** for fetching multiple accounts in one request
7. **API versioning** (currently appears to be v1 implicitly)

**Check the official docs at https://lunchflow.app/api-docs for updates.**

---

## Changelog

### 2025-11-15 (Initial Documentation)
- Reverse-engineered from actual-flow open source implementation
- Documented authentication, endpoints, data structures
- Added comprehensive error handling examples
- Created Ruby and TypeScript client implementations
- Documented use cases for kimonokittens rent system

---

## License & Attribution

This documentation was created through analysis of:
- Lunch Flow public website (lunchflow.app)
- Open source actual-flow project (MIT licensed)
- Community implementations and discussions

Lunch Flow is a product of Lunch Flow Ltd. This documentation is unofficial and created for development purposes.

For official documentation, always refer to: https://lunchflow.app/api-docs

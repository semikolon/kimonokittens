# 46elks SMS API Reference

**Complete API documentation for 46elks SMS service integration**

**Status**: Comprehensive reference compiled for kimonokittens rent reminder system  
**Last Updated**: November 15, 2025  
**Official Docs**: https://46elks.com/docs  
**Base URL**: `https://api.46elks.com/a1/`

---

## Table of Contents

1. [Overview](#overview)
2. [Authentication](#authentication)
3. [Send SMS Endpoint](#send-sms-endpoint)
4. [Delivery Reports (DLR) Webhook](#delivery-reports-dlr-webhook)
5. [Incoming SMS Webhook](#incoming-sms-webhook)
6. [Webhook Security](#webhook-security)
7. [Error Codes](#error-codes)
8. [Rate Limits](#rate-limits)
9. [Pricing](#pricing)
10. [Character Limits & Message Splitting](#character-limits--message-splitting)
11. [Ruby Code Examples](#ruby-code-examples)

---

## Overview

The 46elks API is a simple HTTP API for telecommunications services (SMS, MMS, Voice). Key design principles:

- **Base URL**: `https://api.46elks.com/a1/`
- **Authentication**: HTTP Basic Auth
- **Content-Type**: `application/x-www-form-urlencoded`
- **Asynchronous Events**: Webhooks (HTTP callbacks)
- **Response Format**: JSON

### Prerequisites

- 46elks account with active payment method
- API credentials (username and password)
- For webhooks: Publicly reachable backend service

---

## Authentication

46elks uses **HTTP Basic Authentication** for all API requests.

### Credentials Format

```bash
-u <api_username>:<api_password>
```

### Example (cURL)

```bash
curl https://api.46elks.com/a1/sms \
  -u YOUR_API_USERNAME:YOUR_API_PASSWORD \
  -d from=YourApp \
  -d to=+46700000000 \
  -d message="Test message"
```

### Ruby Example

```ruby
require 'net/http'

uri = URI('https://api.46elks.com/a1/sms')
req = Net::HTTP::Post.new(uri)
req.basic_auth 'YOUR_API_USERNAME', 'YOUR_API_PASSWORD'
```

---

## Send SMS Endpoint

### Endpoint

```
POST https://api.46elks.com/a1/sms
```

### Required Parameters

| Parameter | Type | Example | Description |
|-----------|------|---------|-------------|
| `from` | string | `YourCompany` or `+46700000000` | Sender identifier. Either a text sender ID (max 11 alphanumeric characters) or phone number in E.164 format if you want to receive replies. |
| `to` | string | `+46700000000` | Recipient's phone number in E.164 format. |
| `message` | string | `Hello there!` | The message text to send. |

### Optional Parameters

| Parameter | Type | Example | Description |
|-----------|------|---------|-------------|
| `whendelivered` | string (URL) | `https://yourapp.example/dlrs` | Webhook URL that receives POST requests when delivery status changes. Supports Basic Auth format: `https://user:pass@yourapp.example/dlrs`. Query parameters supported for custom data: `https://yourapp.example/dlr?custom_id=123`. |
| `dryrun` | string | `yes` | Test mode - validates request without sending SMS. Returns `estimated_cost` instead of `cost`. No charge incurred. |
| `flashsms` | string | `yes` | Send as Flash SMS - displays immediately on arrival, not stored in inbox. |
| `dontlog` | string | `message` | Prevent message text from being stored in history. Other parameters still logged. |

### Response Format

#### Success Response (JSON)

```json
{
  "status": "created",
  "direction": "outgoing",
  "from": "YourCompany",
  "created": "2024-05-04T13:37:42.314100",
  "parts": 1,
  "to": "+46700000000",
  "cost": 5000,
  "message": "This is the message sent to the phone.",
  "id": "s70df59406a1b4643b96f3f91e0bfb7b0"
}
```

#### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier for this SMS. Store this for tracking. |
| `status` | string | Current delivery status: `"created"`, `"sent"`, `"failed"`, `"delivered"`. |
| `from` | string | The sender as seen by recipient. |
| `to` | string | Recipient's phone number (E.164 format). |
| `message` | string | The message text sent. |
| `created` | string | UTC timestamp when SMS was created. |
| `delivered` | string | UTC timestamp if SMS successfully delivered (only present when status is `"delivered"`). |
| `cost` | integer | Cost in 10,000ths of account currency. Example: `3500` = 0.35 SEK. |
| `estimated_cost` | integer | Replaces `cost` when `dryrun=yes` is used. |
| `parts` | integer | Number of parts the SMS was divided into. |
| `direction` | string | Always `"outgoing"` for sent SMS. |
| `dontlog` | string | Set to `"message"` if dontlog was enabled. |

#### Dryrun Example Response

```json
{
  "status": "created",
  "direction": "outgoing",
  "from": "Elks",
  "estimated_cost": 10000,
  "to": "+46700000000",
  "parts": 2,
  "message": "This is an example with emoji 🫎"
}
```

---

## Delivery Reports (DLR) Webhook

Delivery reports notify you when SMS delivery status changes.

### Configuration

Set the `whendelivered` parameter when sending SMS:

```bash
curl https://api.46elks.com/a1/sms \
  -u API_USERNAME:API_PASSWORD \
  -d from=YourApp \
  -d to=+46700000000 \
  -d message="Hello" \
  -d whendelivered=https://yourapp.example/elks/dlrs
```

### Webhook Authentication Options

**Basic Auth in URL:**
```
https://username:password@yourserver.example/dlrs
```

**Query Parameters:**
```
https://yourserver.example/dlr?auth_key=SECRET&custom_id=123
```

### Webhook Request

46elks makes an HTTP POST request with `application/x-www-form-urlencoded` content.

#### Example Payload

```
id=s70df59406a1b4643b96f3f91e0bfb7b0&
status=delivered&
delivered=2024-05-04T13:38:15.123000
```

#### Webhook Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | string | The unique SMS ID from the original send response. |
| `status` | string | Current status: `"sent"`, `"delivered"`, or `"failed"`. |
| `delivered` | string | UTC timestamp (only included when `status` is `"delivered"`). |

### Webhook Response Requirements

**Your webhook MUST respond with HTTP status 200-204.**

- If you respond with any other status, 46elks considers the request failed
- Failed requests are retried for **at least 6 hours** and **at least 5 times**
- Response body is ignored

### Status Flow

1. **created** → SMS created in 46elks system
2. **sent** → SMS sent to carrier (DLR webhook triggered)
3. **delivered** → SMS delivered to recipient's phone (DLR webhook triggered)
4. **failed** → Delivery failed (DLR webhook triggered)

---

## Incoming SMS Webhook

Receive SMS sent to your virtual phone number.

### Configuration

Set the `sms_url` parameter on your Virtual Phone Number:

```
https://yourapp.example/elks/sms
```

### Webhook Request

46elks makes an HTTP POST request with `application/x-www-form-urlencoded` content.

#### Example Payload

```
direction=incoming&
id=sf8425555e5d8db61dda7a7b3f1b91bdb&
from=%2B46706861004&
to=%2B46706860000&
created=2018-07-13T13%3A57%3A23.741000&
message=Hello%20how%20are%20you%3F
```

#### Webhook Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | string | Unique ID of the incoming message. |
| `from` | string | Sender's phone number. |
| `to` | string | Your virtual phone number that received the SMS. |
| `message` | string | The SMS content (URL-decoded). |
| `direction` | string | Always `"incoming"` for received SMS. |
| `created` | string | UTC timestamp when SMS was received. |

### Webhook Response Requirements

**Your webhook MUST respond with HTTP status 200-204.**

- Same retry logic as delivery reports (6 hours, 5+ attempts)

### Automatic Replies

You can reply directly in your webhook response instead of calling POST /sms separately:

**Response body (plain text):**
```
The current time is 08:14.
```

This sends an SMS reply immediately without additional API call.

---

## Webhook Security

### Authentication Methods

46elks **does NOT use HMAC-SHA256 signature verification** like Stripe/GitHub. Instead, use these authentication methods:

#### 1. Basic Authentication (Recommended)

Include credentials in the webhook URL:

```ruby
whendelivered = "https://#{username}:#{password}@yourapp.example/dlrs"
```

Verify in your webhook handler:

```ruby
# Rack-based apps (Sinatra, Rails)
def authenticate!
  @auth ||= Rack::Auth::Basic::Request.new(request.env)
  unless @auth.provided? && @auth.basic? && @auth.credentials == [USERNAME, PASSWORD]
    halt 401, "Unauthorized"
  end
end

post '/dlrs' do
  authenticate!
  # Handle delivery report
end
```

#### 2. URL Query Parameters

Include secret token in URL:

```ruby
whendelivered = "https://yourapp.example/dlrs?token=#{SecureRandom.hex(32)}"
```

Verify in your handler:

```ruby
post '/dlrs' do
  halt 401, "Unauthorized" unless params[:token] == ENV['WEBHOOK_SECRET']
  # Handle delivery report
end
```

#### 3. JWT (JSON Web Tokens)

For advanced authentication, encode a JWT and include it as a query parameter or in Basic Auth.

### Security Best Practices

1. **Always use HTTPS** for webhook URLs
2. **Use authentication** - never expose unauthenticated webhook endpoints
3. **Validate all input** - don't trust webhook data blindly
4. **Respond quickly** (within 200-204 range) to avoid retries
5. **Log webhook failures** for debugging
6. **Use unique tokens per environment** (dev, staging, production)

### IP Allowlisting

46elks does not publish a fixed IP range for webhooks. Use authentication instead of IP filtering.

---

## Error Codes

### HTTP Status Codes

46elks uses standard HTTP status codes:

| Code | Category | Description |
|------|----------|-------------|
| **2xx** | Success | Request succeeded |
| **3xx** | Redirection | Request redirected |
| **4xx** | Client Error | Problem with your request |
| **5xx** | Server Error | 46elks internal error |

### Specific Error Codes

#### 403 Forbidden - Insufficient Credits

When your account balance is too low:

**Response:**
```json
{
  "error": "Not enough credits"
}
```

**Action Required:** Add credits to your 46elks account

#### 401 Unauthorized

Invalid API credentials.

**Action Required:** Verify API username and password

#### 400 Bad Request

Invalid parameters (e.g., malformed phone number, missing required fields).

**Action Required:** Check request parameters against API documentation

### Error Response Format

```json
{
  "error": "Description of what went wrong"
}
```

### Handling Errors in Ruby

```ruby
require 'net/http'
require 'json'

uri = URI('https://api.46elks.com/a1/sms')
req = Net::HTTP::Post.new(uri)
req.basic_auth API_USERNAME, API_PASSWORD
req.set_form_data(from: 'YourApp', to: '+46700000000', message: 'Test')

response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
  http.request(req)
end

case response
when Net::HTTPSuccess
  result = JSON.parse(response.body)
  puts "SMS sent! ID: #{result['id']}"
when Net::HTTPForbidden
  puts "Error: Insufficient credits"
when Net::HTTPUnauthorized
  puts "Error: Invalid API credentials"
else
  puts "Error #{response.code}: #{response.body}"
end
```

---

## Rate Limits

### SMS Rate Limit

**Default:** 100 SMS per minute per account

**Behavior:** Messages exceeding this limit are **queued** (not rejected)
- Excess messages are sent as fast as possible in order
- No error responses - all messages eventually send

**Higher Limits:** Contact 46elks support if you need > 100 SMS/min

### Throughput Notes

From official documentation:

> Default maximum throughput is 100 SMS per minute per account. Additional messages will be queued and sent in-order. Contact support if you require additional throughput.

### No Hard API Rate Limit

Unlike many APIs, 46elks does **not** return 429 (Too Many Requests) errors. The queue-based approach ensures all messages are sent.

---

## Pricing

### Sweden Pricing (November 2025)

| Service | Cost (EUR) | Cost (SEK) | Monthly Fee |
|---------|-----------|-----------|-------------|
| **Send SMS** | €0.047 per part | ~0.50 SEK per part | €0 (no API access fee) |
| **Receive SMS** | €0 per message | 0 SEK | €3 (virtual number required) |
| **Virtual Phone Number** | - | - | €3/month |

**All prices exclude VAT.**

### Cost Calculation Examples

#### Single SMS (160 characters or less)

```
Cost: €0.047 = ~0.50 SEK per part
Parts: 1
Total: €0.047
```

#### Multi-part SMS (320 characters, GSM charset)

```
Characters per part: 153 (for multi-part GSM)
Parts needed: 320 ÷ 153 = 2.09 → 3 parts
Cost per part: €0.047
Total: 3 × €0.047 = €0.141
```

#### Emoji SMS (70 characters)

```
Encoding: UTF-16 (emoji forces this)
Characters per part: 70
Parts needed: 1
Cost: €0.047
```

### Cost Response Field

The `cost` field in API responses uses **10,000ths of account currency:**

```json
{
  "cost": 5000  // = 0.50 SEK if account currency is SEK
}
```

**Formula:** `actual_cost = cost / 10000`

### Estimating Costs with Dryrun

Use `dryrun=yes` to preview cost without sending:

```bash
curl https://api.46elks.com/a1/sms \
  -u API_USERNAME:API_PASSWORD \
  -d from=YourApp \
  -d to=+46700000000 \
  -d message="Long message with emojis 🦌🫎" \
  -d dryrun=yes
```

Response includes `estimated_cost` instead of `cost`.

---

## Character Limits & Message Splitting

### Character Encoding

SMS messages use two encoding schemes:

#### 1. GSM 03.38 Basic Character Set

**Supported characters:**
- Letters: A-Z, a-z
- Numbers: 0-9
- Basic punctuation: `. , ! ? ( ) - ' " : ;`
- Basic symbols: `@ £ $ ¥ € & _ = + * # /`

**Single SMS:** Up to **160 characters**

**Multi-part SMS:** Up to **153 characters per part**

#### 2. UTF-16 (Unicode)

**Triggered by:**
- Emojis (🦌, 🫎, ❤️, etc.)
- Non-GSM characters (Chinese, Arabic, special symbols)

**Single SMS:** Up to **70 characters**

**Multi-part SMS:** Up to **67 characters per part**

### Message Splitting Rules

#### GSM Messages

| Total Length | Parts | Chars per Part |
|--------------|-------|----------------|
| 1-160 | 1 | 160 |
| 161-306 | 2 | 153 each |
| 307-459 | 3 | 153 each |
| 460-612 | 4 | 153 each |

**Formula:** `parts = ⌈message_length / 153⌉` (for length > 160)

#### UTF-16 Messages

| Total Length | Parts | Chars per Part |
|--------------|-------|----------------|
| 1-70 | 1 | 70 |
| 71-134 | 2 | 67 each |
| 135-201 | 3 | 67 each |

**Formula:** `parts = ⌈message_length / 67⌉` (for length > 70)

### Splitting & Joining

46elks automatically:
- **Splits** long messages into parts
- **Reassembles** parts on recipient's phone (using UDH headers)
- **Charges** per part sent

### Testing Character Counts

#### Using Dryrun Parameter

```bash
curl https://api.46elks.com/a1/sms \
  -u API_USERNAME:API_PASSWORD \
  -d from=Test \
  -d to=+46700000000 \
  -d message="Your message here" \
  -d dryrun=yes
```

Check the `parts` field in response.

#### Using 46elks GSM Analyzer

46elks provides a web tool for analyzing messages:
https://46elks.com/gsm-characters

### Line Breaks

Use `\n` for newlines in messages:

```ruby
message = "Hello!\nThis is line 2.\nLine 3 here."
```

Line breaks count toward total character limit.

### Best Practices

1. **Keep messages under 160 chars** (GSM) or 70 chars (UTF-16) when possible
2. **Avoid emojis** unless branding requires them (doubles cost)
3. **Use dryrun** to verify part count before sending
4. **Test with actual phones** - some devices handle multi-part differently
5. **Budget for multi-part** - assume 2x cost for messages with emojis

---

## Ruby Code Examples

### Basic SMS Send

```ruby
require 'net/http'

uri = URI('https://api.46elks.com/a1/sms')
req = Net::HTTP::Post.new(uri)
req.basic_auth 'YOUR_API_USERNAME', 'YOUR_API_PASSWORD'
req.set_form_data(
  from: 'YourApp',
  to: '+46700000000',
  message: 'Hello from Ruby!'
)

res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
  http.request(req)
end

puts res.body
```

### Send with Delivery Report Webhook

```ruby
require 'net/http'

uri = URI('https://api.46elks.com/a1/sms')
req = Net::HTTP::Post.new(uri)
req.basic_auth ENV['ELKS_USERNAME'], ENV['ELKS_PASSWORD']
req.set_form_data(
  from: 'RentReminder',
  to: '+46700000000',
  message: 'Rent due in 3 days: 7,045 kr',
  whendelivered: "https://#{ENV['WEBHOOK_USER']}:#{ENV['WEBHOOK_PASS']}@yourapp.com/elks/dlrs"
)

res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
  http.request(req)
end

result = JSON.parse(res.body)
puts "SMS ID: #{result['id']}, Cost: #{result['cost'] / 10000.0} SEK"
```

### Webhook Handler (Sinatra)

```ruby
require 'sinatra'
require 'json'

# Delivery Report Webhook
post '/elks/dlrs' do
  # 46elks already authenticated via Basic Auth in URL
  sms_id = params[:id]
  status = params[:status]
  delivered_at = params[:delivered]

  puts "SMS #{sms_id} status: #{status}"
  
  # Update your database
  # SmsLog.update(sms_id, status: status, delivered_at: delivered_at)

  status 200  # MUST return 200-204
  body ''
end

# Incoming SMS Webhook
post '/elks/sms' do
  from = params[:from]
  message = params[:message]
  
  puts "Received SMS from #{from}: #{message}"
  
  # Process incoming message
  # ...
  
  # Auto-reply (optional)
  if message.downcase.include?('rent')
    "Your rent for this month is 7,045 kr. Due by the 27th."
  else
    status 200
    body ''
  end
end
```

### Full Integration Example

```ruby
require 'net/http'
require 'json'

class ElksClient
  BASE_URL = 'https://api.46elks.com/a1'
  
  def initialize(username, password)
    @username = username
    @password = password
  end
  
  def send_sms(from:, to:, message:, whendelivered: nil, dryrun: false)
    uri = URI("#{BASE_URL}/sms")
    req = Net::HTTP::Post.new(uri)
    req.basic_auth @username, @password
    
    params = { from: from, to: to, message: message }
    params[:whendelivered] = whendelivered if whendelivered
    params[:dryrun] = 'yes' if dryrun
    
    req.set_form_data(params)
    
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.request(req)
    end
    
    case response
    when Net::HTTPSuccess
      JSON.parse(response.body)
    when Net::HTTPForbidden
      raise "Insufficient credits: #{response.body}"
    when Net::HTTPUnauthorized
      raise "Invalid credentials"
    else
      raise "HTTP #{response.code}: #{response.body}"
    end
  end
end

# Usage
client = ElksClient.new(ENV['ELKS_USERNAME'], ENV['ELKS_PASSWORD'])

# Test with dryrun first
result = client.send_sms(
  from: 'KimonoKittens',
  to: '+46700000000',
  message: 'Rent reminder: 7,045 kr due in 3 days',
  dryrun: true
)

puts "Parts: #{result['parts']}, Estimated cost: #{result['estimated_cost'] / 10000.0} SEK"

# Send for real
result = client.send_sms(
  from: 'KimonoKittens',
  to: '+46700000000',
  message: 'Rent reminder: 7,045 kr due in 3 days',
  whendelivered: 'https://user:pass@yourapp.com/elks/dlrs'
)

puts "Sent! SMS ID: #{result['id']}"
```

### Error Handling Pattern

```ruby
def send_with_retry(client, params, max_retries: 3)
  retries = 0
  begin
    client.send_sms(**params)
  rescue => e
    retries += 1
    if e.message.include?('Insufficient credits')
      # Don't retry - requires manual intervention
      raise e
    elsif retries < max_retries
      sleep(2 ** retries)  # Exponential backoff
      retry
    else
      raise e
    end
  end
end
```

---

## Additional Resources

### Official Documentation

- **Main Docs:** https://46elks.com/docs
- **API Overview:** https://46elks.com/docs/overview
- **Send SMS Guide:** https://46elks.com/docs/send-sms
- **Delivery Reports:** https://46elks.com/docs/sms-delivery-reports
- **Receive SMS:** https://46elks.com/docs/receive-sms
- **Webhook Spec:** https://46elks.com/docs/api-hooks-specification

### Code Examples

- **GitHub Repo:** https://github.com/46elks/46elks-getting-started
- **Ruby Examples:** https://github.com/46elks/46elks-getting-started/tree/master/code-examples/Ruby
- **Ruby Gem (Community):** https://github.com/jage/elk

### Tools

- **GSM Character Analyzer:** https://46elks.com/gsm-characters
- **Pricing Calculator:** https://46elks.com/pricing/sweden
- **Swagger Specification:** https://raw.githubusercontent.com/46elks/46elks-getting-started/master/code-examples/Swagger/46elksAPI.yaml

### Support

- **Email:** sales@46elks.com
- **FAQ:** https://46elks.com/faq
- **SLA Options:** https://46elks.com/sla

---

## Integration Checklist for Kimonokittens

- [ ] Create 46elks account and add payment method
- [ ] Generate API credentials (username/password)
- [ ] Store credentials securely in `.env` file
- [ ] Allocate virtual phone number (if receiving replies)
- [ ] Implement SMS sending function with dryrun testing
- [ ] Set up delivery report webhook handler
- [ ] Implement webhook authentication (Basic Auth recommended)
- [ ] Test webhook endpoint (return 200-204 status)
- [ ] Create database schema for SMS logging
- [ ] Implement retry logic with exponential backoff
- [ ] Add credit balance monitoring
- [ ] Set up production webhook URL (HTTPS required)
- [ ] Test end-to-end flow with real phone number
- [ ] Monitor delivery rates and failures
- [ ] Set up alerts for low credits

---

**Document compiled from official 46elks documentation for the kimonokittens rent reminder system integration.**

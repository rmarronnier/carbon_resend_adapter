# Carbon Resend Adapter

Integration for Lucky's [Carbon](https://github.com/luckyframework/carbon) email library and [Resend](https://resend.com).

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     carbon_resend_adapter:
       github: rmarronnier/carbon_resend_adapter
   ```

2. Run `shards install`.

## Usage

Set your Resend API key:

```bash
export RESEND_API_KEY=...
```

Then configure your adapter (for example in `config/email.cr`):

```crystal
require "carbon_resend_adapter"

BaseEmail.configure do |settings|
  if LuckyEnv.test?
    settings.adapter = Carbon::DevAdapter.new
  elsif resend_api_key = ENV["RESEND_API_KEY"]?
    settings.adapter = Carbon::ResendAdapter.new(api_key: resend_api_key)
  elsif LuckyEnv.development?
    settings.adapter = Carbon::DevAdapter.new(print_emails: true)
  else
    puts "Missing RESEND_API_KEY".colorize.red
    exit(1)
  end
end
```

Set a valid sender on your emails (must be allowed by Resend):

```crystal
class WelcomeEmail < Carbon::Email
  to Carbon::Address.new("user@example.com")
  from Carbon::Address.new("Acme", "onboarding@resend.dev")
  subject "Welcome"
  templates text
end
```

## Features

### Carbon delivery (`deliver_now`)

- Sends Carbon emails using `POST /emails`.
- Supports `from`, `to`, `cc`, `bcc`, `reply_to`, `headers`, `text`, `html`.
- Supports Carbon attachments (`AttachFile`, `AttachIO`, `ResourceFile`, `ResourceIO`) as base64 content.
- Raises `Carbon::ResendResponseFailedError` with `status_code`, `method`, and `path` on non-success responses.

### Latest Resend Emails API support

The adapter now exposes methods covering the current Resend Emails API:

- `send_email(request)` (`POST /emails`)
- `send_batch(requests, idempotency_key: nil)` (`POST /emails/batch`)
- `list_emails(limit: nil, after: nil, before: nil)` (`GET /emails`)
- `retrieve_email(email_id)` (`GET /emails/{email_id}`)
- `update_email(email_id, request)` (`PATCH /emails/{email_id}`)
- `cancel_email(email_id)` (`POST /emails/{email_id}/cancel`)
- `list_email_attachments(email_id, limit: nil, after: nil, before: nil)` (`GET /emails/{email_id}/attachments`)
- `retrieve_email_attachment(email_id, attachment_id)` (`GET /emails/{email_id}/attachments/{attachment_id}`)

`SendEmailRequest` supports all latest send fields:

- `template`
- `tags`
- `scheduled_at`
- request `idempotency_key` (maps to `Idempotency-Key` header)
- `attachments` with either inline `content` or remote `path`

## Resend-specific options for Carbon emails

If you need fields that Carbon does not model directly (e.g. `template`, `tags`, `scheduled_at`, request idempotency key), include `Carbon::ResendAdapter::OptionsProvider`:

```crystal
class WelcomeEmail < Carbon::Email
  include Carbon::ResendAdapter::OptionsProvider

  to Carbon::Address.new("user@example.com")
  from Carbon::Address.new("Acme", "onboarding@resend.dev")
  subject "Welcome"

  def resend_options
    Carbon::ResendAdapter::SendEmailOverrides.new(
      template: Carbon::ResendAdapter::Template.new(
        id: "tmpl_123",
        variables: {
          "first_name" => "Jane",
          "plan"       => "pro",
        }
      ),
      tags: [
        Carbon::ResendAdapter::Tag.new("flow", "onboarding"),
        Carbon::ResendAdapter::Tag.new("tenant", "acme"),
      ],
      scheduled_at: "2026-03-01T10:00:00.000Z",
      idempotency_key: "welcome-email-user-42"
    )
  end
end
```

If `template` is set, `text` and `html` are omitted from the payload as required by Resend.

## Direct API request example

```crystal
adapter = Carbon::ResendAdapter.new(api_key: ENV["RESEND_API_KEY"])

request = Carbon::ResendAdapter::SendEmailRequest.new(
  from: "Acme <onboarding@resend.dev>",
  to: ["user@example.com"],
  subject: "Welcome",
  template: Carbon::ResendAdapter::Template.new(
    id: "tmpl_123",
    variables: {"first_name" => "Jane"}
  ),
  tags: [Carbon::ResendAdapter::Tag.new("flow", "onboarding")],
  idempotency_key: "welcome-user-42"
)

response = adapter.send_email(request)
puts response.status_code
puts response.body
```

## Development

```bash
shards install
crystal tool format
crystal spec
```

## License

MIT

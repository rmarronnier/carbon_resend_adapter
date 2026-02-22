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

- Sends Carbon emails using Resend `POST /emails`.
- Supports `to`, `cc`, `bcc`, `reply_to`, `headers`, `text`, `html`.
- Supports Carbon attachments (`AttachFile`, `AttachIO`, `ResourceFile`, `ResourceIO`).
- Raises `Carbon::ResendResponseFailedError` on non-success responses.

## Development

```bash
shards install
crystal tool format --check
crystal spec
```

## License

MIT

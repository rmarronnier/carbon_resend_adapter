require "uuid"
require "./spec_helper"
require "./support/*"

private class FakeEmailWithAttachment < Carbon::Email
  to Carbon::Address.new("to@example.com")
  from Carbon::Address.new("from@example.com")
  subject "Attachment"

  def text_body
    "Attachment body"
  end

  def attachments
    [
      {
        io:        IO::Memory.new("hello world"),
        file_name: "hello.txt",
        mime_type: "text/plain",
      },
    ]
  end
end

private class FakeEmailWithFileAttachment < Carbon::Email
  to Carbon::Address.new("to@example.com")
  from Carbon::Address.new("from@example.com")
  subject "File attachment"

  def text_body
    "Attachment body"
  end

  def attachments
    [
      {
        file_path: "/tmp/resend-file-attachment.txt",
        file_name: nil,
        mime_type: "text/plain",
      },
    ]
  end
end

private class FakeEmailWithResendOptions < Carbon::Email
  include Carbon::ResendAdapter::OptionsProvider

  to Carbon::Address.new("to@example.com")
  cc Carbon::Address.new("cc@example.com")
  from Carbon::Address.new("from@example.com")
  subject "Templated"
  reply_to "reply@example.com"
  header "X-Base", "1"

  def text_body
    "ignored text"
  end

  def html_body
    "<p>ignored html</p>"
  end

  def attachments
    [
      {
        io:        IO::Memory.new("inline bytes"),
        file_name: "inline.txt",
        mime_type: "text/plain",
      },
    ]
  end

  def resend_options : Carbon::ResendAdapter::SendEmailOverrides
    Carbon::ResendAdapter::SendEmailOverrides.new(
      bcc: ["audit@example.com"],
      reply_to: ["first-reply@example.com", "second-reply@example.com"],
      template: Carbon::ResendAdapter::Template.new(
        id: "tmpl_123",
        variables: {
          "name"  => "Remy",
          "count" => 3,
        }
      ),
      headers: {"X-Extra" => "2"},
      scheduled_at: "2026-02-28T12:30:00.000Z",
      attachments: [
        Carbon::ResendAdapter::Attachment.new(
          filename: "from-url.pdf",
          path: "https://cdn.example.com/file.pdf",
          content_type: "application/pdf"
        ),
      ],
      tags: [
        Carbon::ResendAdapter::Tag.new("category", "welcome"),
        Carbon::ResendAdapter::Tag.new("tenant", "acme"),
      ],
      idempotency_key: "idem_123"
    )
  end
end

describe Carbon::ResendAdapter do
  it "posts a resend-compatible payload" do
    WebMock.wrap do
      expected_body = {
        "from"     => "\"Sender\" <from@example.com>",
        "to"       => ["to@example.com"],
        "subject"  => "Welcome",
        "bcc"      => ["bcc@example.com"],
        "cc"       => ["cc@example.com"],
        "reply_to" => "reply@example.com",
        "html"     => "<p>Hello HTML</p>",
        "text"     => "Plain body",
        "headers"  => {"X-Tamis-Test" => "1"},
      }.to_json

      stub = WebMock
        .stub(:post, "https://api.resend.com/emails")
        .with(
          body: expected_body,
          headers: {
            "Authorization" => "Bearer resend-key",
            "Content-Type"  => "application/json",
          }
        )
        .to_return(status: 200, body: {id: "email_123"}.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").deliver_now(FakeEmail.new)

      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "sends attachments as base64" do
    WebMock.wrap do
      expected_body = {
        "from"        => "from@example.com",
        "to"          => ["to@example.com"],
        "subject"     => "Attachment",
        "text"        => "Attachment body",
        "attachments" => [
          {
            "filename"     => "hello.txt",
            "content"      => "aGVsbG8gd29ybGQ=",
            "content_type" => "text/plain",
          },
        ],
      }.to_json

      stub = WebMock
        .stub(:post, "https://api.resend.com/emails")
        .with(body: expected_body)
        .to_return(status: 200, body: {id: "email_456"}.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").deliver_now(FakeEmailWithAttachment.new)

      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "encodes file attachments and infers filename" do
    File.write("/tmp/resend-file-attachment.txt", "file body")

    WebMock.wrap do
      expected_body = {
        "from"        => "from@example.com",
        "to"          => ["to@example.com"],
        "subject"     => "File attachment",
        "text"        => "Attachment body",
        "attachments" => [
          {
            "filename"     => "resend-file-attachment.txt",
            "content"      => "ZmlsZSBib2R5",
            "content_type" => "text/plain",
          },
        ],
      }.to_json

      stub = WebMock
        .stub(:post, "https://api.resend.com/emails")
        .with(body: expected_body)
        .to_return(status: 200, body: {id: "email_file"}.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").deliver_now(FakeEmailWithFileAttachment.new)
      response.status_code.should eq 200
      stub.calls.should eq 1
    ensure
      File.delete("/tmp/resend-file-attachment.txt") if File.exists?("/tmp/resend-file-attachment.txt")
    end
  end

  it "supports resend-only options through OptionsProvider" do
    WebMock.wrap do
      expected_body = {
        "from"     => "from@example.com",
        "to"       => ["to@example.com"],
        "subject"  => "Templated",
        "bcc"      => ["audit@example.com"],
        "cc"       => ["cc@example.com"],
        "reply_to" => ["first-reply@example.com", "second-reply@example.com"],
        "template" => {
          "id"        => "tmpl_123",
          "variables" => {
            "name"  => "Remy",
            "count" => 3,
          },
        },
        "headers" => {
          "X-Base"  => "1",
          "X-Extra" => "2",
        },
        "scheduled_at" => "2026-02-28T12:30:00.000Z",
        "attachments"  => [
          {
            "filename"     => "inline.txt",
            "content"      => "aW5saW5lIGJ5dGVz",
            "content_type" => "text/plain",
          },
          {
            "filename"     => "from-url.pdf",
            "path"         => "https://cdn.example.com/file.pdf",
            "content_type" => "application/pdf",
          },
        ],
        "tags" => [
          {"name" => "category", "value" => "welcome"},
          {"name" => "tenant", "value" => "acme"},
        ],
      }.to_json

      stub = WebMock
        .stub(:post, "https://api.resend.com/emails")
        .with(
          body: expected_body,
          headers: {
            "Authorization"   => "Bearer resend-key",
            "Content-Type"    => "application/json",
            "Idempotency-Key" => "idem_123",
          }
        )
        .to_return(status: 200, body: {id: "email_template"}.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").deliver_now(FakeEmailWithResendOptions.new)
      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "sends a request object directly with latest fields" do
    request = Carbon::ResendAdapter::SendEmailRequest.new(
      from: "Acme <from@example.com>",
      to: "to@example.com",
      subject: "Subject",
      cc: ["cc@example.com"],
      bcc: ["bcc@example.com"],
      reply_to: ["reply@example.com"],
      text: "text body",
      html: "<strong>html body</strong>",
      template: Carbon::ResendAdapter::Template.new(
        id: "tmpl_123",
        variables: {"account_id" => 42}
      ),
      headers: {"X-Header" => "value"},
      scheduled_at: "2026-03-01T10:00:00.000Z",
      attachments: [
        Carbon::ResendAdapter::Attachment.new(
          filename: "example.pdf",
          path: "https://cdn.example.com/example.pdf"
        ),
      ],
      tags: [Carbon::ResendAdapter::Tag.new("flow", "welcome")],
      idempotency_key: "idem_request_123"
    )

    WebMock.wrap do
      stub = WebMock
        .stub(:post, "https://api.resend.com/emails")
        .with(
          body: request.to_json,
          headers: {
            "Authorization"   => "Bearer resend-key",
            "Idempotency-Key" => "idem_request_123",
          }
        )
        .to_return(status: 200, body: {id: "email_request"}.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").send_email(request)
      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "sends batch emails" do
    request_a = Carbon::ResendAdapter::SendEmailRequest.new(
      from: "from@example.com",
      to: ["a@example.com"],
      subject: "First",
      text: "A"
    )

    request_b = Carbon::ResendAdapter::SendEmailRequest.new(
      from: "from@example.com",
      to: ["b@example.com"],
      subject: "Second",
      text: "B"
    )

    expected_batch_payload = JSON.build do |json|
      json.array do
        request_a.to_json(json)
        request_b.to_json(json)
      end
    end

    WebMock.wrap do
      stub = WebMock
        .stub(:post, "https://api.resend.com/emails/batch")
        .with(
          body: expected_batch_payload,
          headers: {
            "Authorization"   => "Bearer resend-key",
            "Idempotency-Key" => "idem_batch_123",
          }
        )
        .to_return(status: 200, body: {data: [{id: "email_a"}, {id: "email_b"}]}.to_json)

      response = Carbon::ResendAdapter
        .new(api_key: "resend-key")
        .send_batch([request_a, request_b], idempotency_key: "idem_batch_123")

      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "retrieves a list of emails" do
    WebMock.wrap do
      stub = WebMock
        .stub(:get, "https://api.resend.com/emails")
        .with(query: {"limit" => "10", "after" => "after_1", "before" => "before_1"})
        .to_return(status: 200, body: {object: "list", has_more: false, data: [] of String}.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").list_emails(
        limit: 10,
        after: "after_1",
        before: "before_1"
      )

      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "retrieves a single email" do
    email_id = UUID.random.to_s

    WebMock.wrap do
      stub = WebMock
        .stub(:get, "https://api.resend.com/emails/#{email_id}")
        .to_return(status: 200, body: {id: email_id}.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").retrieve_email(email_id)
      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "updates a single scheduled email" do
    email_id = UUID.random.to_s
    request = Carbon::ResendAdapter::UpdateEmailRequest.new(
      scheduled_at: "2026-03-03T10:00:00.000Z"
    )

    WebMock.wrap do
      stub = WebMock
        .stub(:patch, "https://api.resend.com/emails/#{email_id}")
        .with(body: request.to_json)
        .to_return(status: 200, body: request.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").update_email(email_id, request)
      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "cancels a scheduled email" do
    email_id = UUID.random.to_s

    WebMock.wrap do
      stub = WebMock
        .stub(:post, "https://api.resend.com/emails/#{email_id}/cancel")
        .to_return(status: 200, body: {id: email_id, last_event: "canceled"}.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").cancel_email(email_id)
      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "retrieves sent email attachments" do
    email_id = UUID.random.to_s

    WebMock.wrap do
      stub = WebMock
        .stub(:get, "https://api.resend.com/emails/#{email_id}/attachments")
        .with(query: {"limit" => "2", "after" => "a", "before" => "b"})
        .to_return(status: 200, body: {object: "list", has_more: false, data: [] of String}.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").list_email_attachments(
        email_id,
        limit: 2,
        after: "a",
        before: "b"
      )

      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "retrieves a single sent attachment" do
    email_id = UUID.random.to_s
    attachment_id = UUID.random.to_s

    WebMock.wrap do
      stub = WebMock
        .stub(:get, "https://api.resend.com/emails/#{email_id}/attachments/#{attachment_id}")
        .to_return(status: 200, body: {id: attachment_id}.to_json)

      response = Carbon::ResendAdapter.new(api_key: "resend-key").retrieve_email_attachment(email_id, attachment_id)
      response.status_code.should eq 200
      stub.calls.should eq 1
    end
  end

  it "raises rich errors on non-success responses" do
    WebMock.wrap do
      WebMock
        .stub(:post, "https://api.resend.com/emails")
        .to_return(status: 422, body: "invalid resend payload")

      error = expect_raises(Carbon::ResendResponseFailedError, /invalid resend payload/) do
        Carbon::ResendAdapter.new(api_key: "resend-key").deliver_now(FakeEmail.new)
      end

      error.status_code.should eq 422
      error.method.should eq "POST"
      error.path.should eq "/emails"
    end
  end

  it "validates attachments require content or path" do
    expect_raises(ArgumentError, /either content or path/) do
      Carbon::ResendAdapter::Attachment.new(filename: "invalid.txt")
    end
  end
end

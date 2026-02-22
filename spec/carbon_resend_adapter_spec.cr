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

describe Carbon::ResendAdapter do
  it "posts a resend-compatible payload" do
    WebMock.wrap do
      expected_body = {
        "from"     => "\"Sender\" <from@example.com>",
        "to"       => ["to@example.com"],
        "cc"       => ["cc@example.com"],
        "bcc"      => ["bcc@example.com"],
        "subject"  => "Welcome",
        "text"     => "Plain body",
        "html"     => "<p>Hello HTML</p>",
        "reply_to" => "reply@example.com",
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

  it "raises on non-success responses" do
    WebMock.wrap do
      WebMock
        .stub(:post, "https://api.resend.com/emails")
        .to_return(status: 422, body: "invalid resend payload")

      expect_raises(Carbon::ResendResponseFailedError, /invalid resend payload/) do
        Carbon::ResendAdapter.new(api_key: "resend-key").deliver_now(FakeEmail.new)
      end
    end
  end
end

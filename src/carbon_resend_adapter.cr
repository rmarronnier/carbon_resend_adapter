require "base64"
require "carbon"
require "http"
require "json"
require "./errors"

class Carbon::ResendAdapter < Carbon::Adapter
  VERSION     = "0.1.0"
  BASE_URI    = "api.resend.com"
  EMAILS_PATH = "/emails"

  private getter api_key : String

  def initialize(@api_key : String)
  end

  def deliver_now(email : Carbon::Email)
    response = client.post(EMAILS_PATH, body: payload_for(email))
    return response if response.success?

    raise Carbon::ResendResponseFailedError.new(response.body)
  end

  private def payload_for(email : Carbon::Email) : String
    JSON.build do |json|
      json.object do
        json.field "from", format_address(email.from)

        json.field "to" do
          json.array do
            email.to.each { |address| json.string(format_address(address)) }
          end
        end

        unless email.cc.empty?
          json.field "cc" do
            json.array do
              email.cc.each { |address| json.string(format_address(address)) }
            end
          end
        end

        unless email.bcc.empty?
          json.field "bcc" do
            json.array do
              email.bcc.each { |address| json.string(format_address(address)) }
            end
          end
        end

        json.field "subject", email.subject

        if text_body = email.text_body
          json.field "text", text_body unless text_body.empty?
        end

        if html_body = email.html_body
          json.field "html", html_body unless html_body.empty?
        end

        if reply_to = reply_to_header(email.headers)
          json.field "reply_to", reply_to
        end

        headers = headers_without_reply_to(email.headers)
        unless headers.empty?
          json.field "headers" do
            json.object do
              headers.each do |key, value|
                json.field key, value
              end
            end
          end
        end

        attachments = resend_attachments(email.attachments)
        unless attachments.empty?
          json.field "attachments" do
            json.array do
              attachments.each do |attachment|
                json.object do
                  json.field "filename", attachment[:filename]
                  json.field "content", attachment[:content]
                  if content_type = attachment[:content_type]
                    json.field "content_type", content_type
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  private def resend_attachments(attachments : Array(Carbon::Attachment))
    attachments.map do |attachment|
      case attachment
      in AttachFile, ResourceFile
        {
          filename:     attachment[:file_name] || File.basename(attachment[:file_path]),
          content:      Base64.strict_encode(File.read(attachment[:file_path])),
          content_type: attachment[:mime_type],
        }
      in AttachIO, ResourceIO
        {
          filename:     attachment[:file_name],
          content:      Base64.strict_encode(attachment[:io].gets_to_end),
          content_type: attachment[:mime_type],
        }
      end
    end
  end

  private def format_address(address : Carbon::Address) : String
    address.to_s
  end

  private def reply_to_header(headers : Hash(String, String)) : String?
    headers.each do |key, value|
      return value if key.downcase == "reply-to"
    end
    nil
  end

  private def headers_without_reply_to(headers : Hash(String, String)) : Hash(String, String)
    headers.reject { |key, _| key.downcase == "reply-to" }
  end

  @_client : HTTP::Client?

  private def client : HTTP::Client
    @_client ||= HTTP::Client.new(BASE_URI, port: 443, tls: true).tap do |http_client|
      http_client.before_request do |request|
        request.headers["Authorization"] = "Bearer #{api_key}"
        request.headers["Content-Type"] = "application/json"
      end
    end
  end
end

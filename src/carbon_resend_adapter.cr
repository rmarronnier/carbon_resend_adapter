require "base64"
require "carbon"
require "http"
require "json"
require "uri"
require "./errors"

class Carbon::ResendAdapter < Carbon::Adapter
  VERSION     = "0.2.0"
  BASE_URI    = "api.resend.com"
  EMAILS_PATH = "/emails"

  alias AddressInput = String | Array(String)
  alias TemplateVariable = String | Int32 | Int64 | Float32 | Float64
  alias TemplateVariables = Hash(String, TemplateVariable)

  module OptionsProvider
    abstract def resend_options : Carbon::ResendAdapter::SendEmailOverrides
  end

  struct Tag
    getter name : String
    getter value : String

    def initialize(@name : String, @value : String)
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "name", name
        json.field "value", value
      end
    end
  end

  struct Template
    getter id : String
    getter variables : TemplateVariables?

    def initialize(@id : String, variables : Hash(String, V)? = nil) forall V
      @variables = normalize_variables(variables)
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "id", id

        if template_variables = variables
          json.field "variables" do
            json.object do
              template_variables.each do |key, value|
                json.field key, value
              end
            end
          end
        end
      end
    end

    private def normalize_variables(variables : Hash(String, V)?) : TemplateVariables? forall V
      return nil unless variables

      normalized = {} of String => TemplateVariable
      variables.each do |key, value|
        case value
        when String, Int32, Int64, Float32, Float64
          normalized[key] = value
        else
          raise ArgumentError.new("Template variables only support String or Number values")
        end
      end

      normalized
    end
  end

  struct Attachment
    getter filename : String?
    getter content : String?
    getter path : String?
    getter content_type : String?

    def initialize(
      @filename : String? = nil,
      @content : String? = nil,
      @path : String? = nil,
      @content_type : String? = nil,
    )
      if content.nil? && path.nil?
        raise ArgumentError.new("Attachment requires either content or path")
      end
    end

    def to_json(json : JSON::Builder)
      json.object do
        if value = filename
          json.field "filename", value
        end

        if value = content
          json.field "content", value
        end

        if value = path
          json.field "path", value
        end

        if value = content_type
          json.field "content_type", value
        end
      end
    end
  end

  struct SendEmailOverrides
    getter bcc : AddressInput?
    getter cc : AddressInput?
    getter reply_to : AddressInput?
    getter html : String?
    getter text : String?
    getter template : Template?
    getter headers : Hash(String, String)?
    getter scheduled_at : String?
    getter attachments : Array(Attachment)?
    getter tags : Array(Tag)?
    getter idempotency_key : String?

    def initialize(
      @bcc : AddressInput? = nil,
      @cc : AddressInput? = nil,
      @reply_to : AddressInput? = nil,
      @html : String? = nil,
      @text : String? = nil,
      @template : Template? = nil,
      @headers : Hash(String, String)? = nil,
      @scheduled_at : String? = nil,
      @attachments : Array(Attachment)? = nil,
      @tags : Array(Tag)? = nil,
      @idempotency_key : String? = nil,
    )
    end
  end

  struct SendEmailRequest
    getter from : String
    getter to : AddressInput
    getter subject : String
    getter bcc : AddressInput?
    getter cc : AddressInput?
    getter reply_to : AddressInput?
    getter html : String?
    getter text : String?
    getter template : Template?
    getter headers : Hash(String, String)?
    getter scheduled_at : String?
    getter attachments : Array(Attachment)?
    getter tags : Array(Tag)?
    getter idempotency_key : String?

    def initialize(
      @from : String,
      @to : AddressInput,
      @subject : String,
      @bcc : AddressInput? = nil,
      @cc : AddressInput? = nil,
      @reply_to : AddressInput? = nil,
      @html : String? = nil,
      @text : String? = nil,
      @template : Template? = nil,
      @headers : Hash(String, String)? = nil,
      @scheduled_at : String? = nil,
      @attachments : Array(Attachment)? = nil,
      @tags : Array(Tag)? = nil,
      @idempotency_key : String? = nil,
    )
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "from", from
        write_address_field(json, "to", to)
        json.field "subject", subject

        if value = bcc
          write_address_field(json, "bcc", value)
        end

        if value = cc
          write_address_field(json, "cc", value)
        end

        if value = reply_to
          write_address_field(json, "reply_to", value)
        end

        if value = template
          json.field "template" do
            value.to_json(json)
          end
        else
          if value = html
            json.field "html", value unless value.empty?
          end

          if value = text
            json.field "text", value unless value.empty?
          end
        end

        if value = headers
          unless value.empty?
            json.field "headers" do
              json.object do
                value.each do |key, header_value|
                  json.field key, header_value
                end
              end
            end
          end
        end

        if value = scheduled_at
          json.field "scheduled_at", value
        end

        if value = attachments
          unless value.empty?
            json.field "attachments" do
              json.array do
                value.each do |attachment|
                  attachment.to_json(json)
                end
              end
            end
          end
        end

        if value = tags
          unless value.empty?
            json.field "tags" do
              json.array do
                value.each do |tag|
                  tag.to_json(json)
                end
              end
            end
          end
        end
      end
    end

    def to_json : String
      JSON.build do |json|
        to_json(json)
      end
    end

    private def write_address_field(json : JSON::Builder, key : String, value : AddressInput)
      case value
      when String
        json.field key, value
      when Array(String)
        json.field key do
          json.array do
            value.each { |address| json.string(address) }
          end
        end
      end
    end
  end

  struct UpdateEmailRequest
    getter scheduled_at : String

    def initialize(@scheduled_at : String)
    end

    def to_json : String
      JSON.build do |json|
        json.object do
          json.field "scheduled_at", scheduled_at
        end
      end
    end
  end

  private getter api_key : String

  def initialize(@api_key : String)
  end

  def deliver_now(email : Carbon::Email)
    request = request_from_carbon_email(email)
    response = post_json(EMAILS_PATH, request.to_json, idempotency_key: request.idempotency_key)
    return response if response.success?

    raise_response_failed!(response, method: "POST", path: EMAILS_PATH)
  end

  def send_email(request : SendEmailRequest)
    response = post_json(EMAILS_PATH, request.to_json, idempotency_key: request.idempotency_key)
    return response if response.success?

    raise_response_failed!(response, method: "POST", path: EMAILS_PATH)
  end

  def send_batch(requests : Enumerable(SendEmailRequest), idempotency_key : String? = nil)
    response = post_json(EMAILS_PATH + "/batch", payload_for_batch(requests), idempotency_key: idempotency_key)
    return response if response.success?

    raise_response_failed!(response, method: "POST", path: EMAILS_PATH + "/batch")
  end

  def list_emails(limit : Int32? = nil, after : String? = nil, before : String? = nil)
    path = path_with_query(EMAILS_PATH, limit: limit, after: after, before: before)
    response = client.get(path, headers: request_headers)
    return response if response.success?

    raise_response_failed!(response, method: "GET", path: EMAILS_PATH)
  end

  def retrieve_email(email_id : String)
    path = "#{EMAILS_PATH}/#{encode_path_segment(email_id)}"
    response = client.get(path, headers: request_headers)
    return response if response.success?

    raise_response_failed!(response, method: "GET", path: path)
  end

  def update_email(email_id : String, request : UpdateEmailRequest)
    path = "#{EMAILS_PATH}/#{encode_path_segment(email_id)}"
    response = client.patch(path, body: request.to_json, headers: request_headers)
    return response if response.success?

    raise_response_failed!(response, method: "PATCH", path: path)
  end

  def cancel_email(email_id : String)
    path = "#{EMAILS_PATH}/#{encode_path_segment(email_id)}/cancel"
    response = client.post(path, headers: request_headers)
    return response if response.success?

    raise_response_failed!(response, method: "POST", path: path)
  end

  def list_email_attachments(email_id : String, limit : Int32? = nil, after : String? = nil, before : String? = nil)
    base_path = "#{EMAILS_PATH}/#{encode_path_segment(email_id)}/attachments"
    path = path_with_query(base_path, limit: limit, after: after, before: before)

    response = client.get(path, headers: request_headers)
    return response if response.success?

    raise_response_failed!(response, method: "GET", path: base_path)
  end

  def retrieve_email_attachment(email_id : String, attachment_id : String)
    path = "#{EMAILS_PATH}/#{encode_path_segment(email_id)}/attachments/#{encode_path_segment(attachment_id)}"

    response = client.get(path, headers: request_headers)
    return response if response.success?

    raise_response_failed!(response, method: "GET", path: path)
  end

  private def post_json(path : String, payload : String, idempotency_key : String? = nil)
    client.post(path, body: payload, headers: request_headers(idempotency_key: idempotency_key))
  end

  private def payload_for_batch(requests : Enumerable(SendEmailRequest)) : String
    JSON.build do |json|
      json.array do
        requests.each do |request|
          request.to_json(json)
        end
      end
    end
  end

  private def path_with_query(path : String, limit : Int32? = nil, after : String? = nil, before : String? = nil) : String
    query = HTTP::Params.build do |params|
      params.add("limit", limit.to_s) if limit
      params.add("after", after) if after
      params.add("before", before) if before
    end

    query.empty? ? path : "#{path}?#{query}"
  end

  private def request_from_carbon_email(email : Carbon::Email) : SendEmailRequest
    overrides = email.is_a?(OptionsProvider) ? email.resend_options : nil

    reply_to = overrides.try(&.reply_to) || reply_to_header(email.headers)
    headers = merge_headers(headers_without_reply_to(email.headers), overrides.try(&.headers))

    base_attachments = resend_attachments(email.attachments)
    attachments = merge_attachments(base_attachments, overrides.try(&.attachments))

    SendEmailRequest.new(
      from: format_address(email.from),
      to: email.to.map { |address| format_address(address) },
      subject: email.subject,
      cc: overrides.try(&.cc) || array_or_nil(email.cc.map { |address| format_address(address) }),
      bcc: overrides.try(&.bcc) || array_or_nil(email.bcc.map { |address| format_address(address) }),
      reply_to: reply_to,
      html: overrides.try(&.html) || email.html_body,
      text: overrides.try(&.text) || email.text_body,
      template: overrides.try(&.template),
      headers: headers,
      scheduled_at: overrides.try(&.scheduled_at),
      attachments: attachments,
      tags: overrides.try(&.tags),
      idempotency_key: overrides.try(&.idempotency_key)
    )
  end

  private def merge_headers(primary : Hash(String, String), extra : Hash(String, String)?) : Hash(String, String)?
    merged = primary.dup
    if extra_headers = extra
      merged.merge!(extra_headers)
    end

    merged.empty? ? nil : merged
  end

  private def merge_attachments(primary : Array(Attachment), extra : Array(Attachment)?) : Array(Attachment)?
    merged = primary.dup
    if extra_attachments = extra
      merged.concat(extra_attachments)
    end

    merged.empty? ? nil : merged
  end

  private def array_or_nil(values : Array(String)) : Array(String)?
    values.empty? ? nil : values
  end

  private def resend_attachments(attachments : Array(Carbon::Attachment)) : Array(Attachment)
    attachments.map do |attachment|
      case attachment
      in AttachFile, ResourceFile
        Attachment.new(
          filename: attachment[:file_name] || File.basename(attachment[:file_path]),
          content: Base64.strict_encode(File.read(attachment[:file_path])),
          content_type: attachment[:mime_type]
        )
      in AttachIO, ResourceIO
        Attachment.new(
          filename: attachment[:file_name],
          content: Base64.strict_encode(attachment[:io].gets_to_end),
          content_type: attachment[:mime_type]
        )
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

  private def request_headers(idempotency_key : String? = nil) : HTTP::Headers
    headers = HTTP::Headers{
      "Authorization" => "Bearer #{api_key}",
      "Content-Type"  => "application/json",
    }

    if idempotency_key
      headers["Idempotency-Key"] = idempotency_key
    end

    headers
  end

  private def encode_path_segment(value : String) : String
    URI.encode_path_segment(value)
  end

  private def raise_response_failed!(response : HTTP::Client::Response, method : String, path : String)
    raise Carbon::ResendResponseFailedError.new(
      response.body,
      status_code: response.status_code,
      method: method,
      path: path
    )
  end

  @_client : HTTP::Client?

  private def client : HTTP::Client
    @_client ||= HTTP::Client.new(BASE_URI, port: 443, tls: true)
  end
end

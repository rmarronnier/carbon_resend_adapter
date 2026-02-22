class FakeEmail < Carbon::Email
  to Carbon::Address.new("to@example.com")
  cc Carbon::Address.new("cc@example.com")
  bcc Carbon::Address.new("bcc@example.com")
  from Carbon::Address.new("Sender", "from@example.com")
  subject "Welcome"
  reply_to "reply@example.com"
  header "X-Tamis-Test", "1"

  def text_body
    "Plain body"
  end

  def html_body
    "<p>Hello HTML</p>"
  end
end

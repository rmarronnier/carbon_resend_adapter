module Carbon
  class ResendError < Exception
  end

  class ResendResponseFailedError < ResendError
    getter response_body : String
    getter status_code : Int32?
    getter method : String?
    getter path : String?

    def initialize(
      @response_body : String,
      @status_code : Int32? = nil,
      @method : String? = nil,
      @path : String? = nil,
    )
      super(error_message)
    end

    private def error_message : String
      if method && path && status_code
        "#{method} #{path} failed with status #{status_code}: #{response_body}"
      elsif status_code
        "Resend request failed with status #{status_code}: #{response_body}"
      else
        response_body
      end
    end
  end
end

class TestController < ApplicationController
  def test_logging
    Rails.logger.info "************* Test info from rails_3_app"

    @outputs = [logger.class]
    render text: logger.class.to_s
  end
end

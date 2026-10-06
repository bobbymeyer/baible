class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # When the app says no, whoever asked sees why (Refusal).
  rescue_from Refusal do |refusal|
    redirect_back_or_to root_path, alert: refusal.message, status: :see_other
  end
end

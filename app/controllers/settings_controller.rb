# frozen_string_literal: true

# The app's settings (SiteSetting): where ComfyUI and the language model
# answer, and their default models, with a check that the app can reach them.
class SettingsController < ApplicationController
  def show
    @setting = SiteSetting.first || SiteSetting.new
  end

  def update
    @setting = SiteSetting.first || SiteSetting.new
    if @setting.update(params.expect(site_setting: SiteSetting::FIELDS))
      Comfy.forget_capabilities!
      redirect_to settings_path(check: 1, anchor: "connection"), notice: "Settings saved.", status: :see_other
    else
      render :show, status: :unprocessable_content
    end
  end
end

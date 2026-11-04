require "digest"

# Forgot password (login page): the employee types the Employee Code, ESS mails a one-time link to the
# email saved on that employee (through krai, like every other ESS mail). The link is valid for 2 hours
# and works once. The page never says whether a code exists, so nobody can probe employee codes.
class PasswordResetsController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :load_user_by_token, only: %i[edit update]

  VALID_FOR = 2.hours
  RESEND_AFTER = 2.minutes

  def new; end

  def create
    user = User.where(active: true).where("LOWER(TRIM(emp_code)) = ?", params[:emp_code].to_s.strip.downcase).first
    if user&.email.to_s.include?("@") && !(user.reset_password_sent_at && user.reset_password_sent_at > RESEND_AFTER.ago)
      token = SecureRandom.urlsafe_base64(32)
      user.update_columns(reset_password_token: Digest::SHA256.hexdigest(token), reset_password_sent_at: Time.current)
      EssMailRelay.password_reset(user, reset_password_path(token: token, script_name: ""))
    end
    redirect_to forgot_password_path(sent: 1)
  end

  def edit; end

  def update
    pw, confirm = params[:password].to_s, params[:password_confirmation].to_s
    if pw.length < User::PASSWORD_MINIMUM_LENGTH
      flash.now[:alert] = "Password must be at least #{User::PASSWORD_MINIMUM_LENGTH} characters."
    elsif pw != confirm
      flash.now[:alert] = "The two passwords do not match."
    else
      @user.password = pw
      @user.password_confirmation = confirm
      @user.reset_password_token = nil
      @user.reset_password_sent_at = nil
      if @user.save
        redirect_to new_user_session_path, notice: "Password changed. Please log in with your new password." and return
      end
      flash.now[:alert] = @user.errors.full_messages.to_sentence
    end
    render :edit, status: :unprocessable_entity
  end

  private

  def load_user_by_token
    digest = Digest::SHA256.hexdigest(params[:token].to_s)
    @user = User.where(active: true).find_by(reset_password_token: digest)
    return if @user && @user.reset_password_sent_at && @user.reset_password_sent_at > VALID_FOR.ago

    redirect_to forgot_password_path, alert: "This reset link is invalid or has expired. Please ask for a new one."
  end
end

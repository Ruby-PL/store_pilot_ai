class ApplicationController < ActionController::Base
  MERCHANT_STORE_COOKIE = :store_pilot_store_id

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def current_store
    store_id = cookies.signed[MERCHANT_STORE_COOKIE]
    return if store_id.blank?

    store = Store.find_by(id: store_id)
    return store if store&.active?

    clear_current_store
    nil
  end

  def sign_in_store(store)
    cookies.signed[MERCHANT_STORE_COOKIE] = {
      value: store.id,
      httponly: true,
      same_site: :lax,
      expires: 14.days.from_now
    }
  end

  def clear_current_store
    cookies.delete(MERCHANT_STORE_COOKIE)
  end
end

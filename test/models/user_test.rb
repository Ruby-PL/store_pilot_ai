require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email addresses" do
    user = User.create!(email: "  Merchant@Example.COM ")

    assert_equal "merchant@example.com", user.email
  end

  test "requires a valid email address" do
    user = User.new(email: "not-an-email")

    assert_not user.valid?
    assert_includes user.errors[:email], "is invalid"
  end

  test "email addresses are unique regardless of case" do
    User.create!(email: "merchant@example.com")
    duplicate = User.new(email: "MERCHANT@example.com")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "destroying a user destroys their stores" do
    user = User.create!(email: "merchant@example.com")
    store = user.stores.create!(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_secret")

    user.destroy!

    assert_not Store.exists?(store.id)
  end
end

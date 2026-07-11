require "test_helper"

class Shopify::Apply::ProductFieldsTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :captured

    def initialize(&responder)
      @responder = responder
    end

    def query(_query, variables:)
      @captured = variables
      @responder.call(variables)
    end
  end

  def store
    @store ||= Store.new(shopify_domain: "north-pine.myshopify.com", access_token: "shpat_x")
  end

  test "applies seo fields via productUpdate and reports success" do
    client = FakeClient.new do |_variables|
      { "productUpdate" => { "product" => { "id" => "gid://shopify/Product/1" }, "userErrors" => [] } }
    end

    change = { "product_id" => "gid://shopify/Product/1", "seo_title" => "Great title", "seo_description" => "Great description" }
    outcomes = Shopify::Apply::ProductFields.new(store, [ change ], client:).call

    assert_equal 1, outcomes.size
    assert_empty outcomes.first.errors
    assert_equal({ "seo_title" => "Great title", "seo_description" => "Great description" }, outcomes.first.applied)

    input = client.captured.fetch(:product)
    assert_equal "gid://shopify/Product/1", input[:id]
    assert_equal "Great title", input.dig(:seo, :title)
    assert_equal "Great description", input.dig(:seo, :description)
  end

  test "maps catalog fields to title and descriptionHtml" do
    client = FakeClient.new { |_v| { "productUpdate" => { "product" => {}, "userErrors" => [] } } }

    change = { "product_id" => "gid://shopify/Product/2", "title" => "New name", "description_html" => "<p>New</p>" }
    Shopify::Apply::ProductFields.new(store, [ change ], client:).call

    input = client.captured.fetch(:product)
    assert_equal "New name", input[:title]
    assert_equal "<p>New</p>", input[:descriptionHtml]
    assert_nil input[:seo]
  end

  test "captures Shopify userErrors as failures" do
    client = FakeClient.new do |_v|
      { "productUpdate" => { "product" => nil, "userErrors" => [ { "field" => [ "seo" ], "message" => "Title is too long" } ] } }
    end

    outcomes = Shopify::Apply::ProductFields.new(store, [ { "product_id" => "gid://shopify/Product/3", "seo_title" => "x" } ], client:).call

    assert_equal [ "Title is too long" ], outcomes.first.errors
    assert_empty outcomes.first.applied
  end

  test "captures client errors without raising" do
    client = FakeClient.new { |_v| raise Shopify::Admin::GraphqlClient::Error, "boom" }

    outcomes = Shopify::Apply::ProductFields.new(store, [ { "product_id" => "gid://shopify/Product/4", "seo_title" => "x" } ], client:).call

    assert_equal [ "boom" ], outcomes.first.errors
  end

  test "reports when there is nothing to apply" do
    client = FakeClient.new { |_v| flunk "should not call Shopify" }

    outcomes = Shopify::Apply::ProductFields.new(store, [ { "product_id" => "gid://shopify/Product/5" } ], client:).call

    assert_equal [ "No fields to apply" ], outcomes.first.errors
  end
end

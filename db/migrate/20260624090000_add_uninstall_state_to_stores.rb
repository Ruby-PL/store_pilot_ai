class AddUninstallStateToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :active, :boolean, null: false, default: true
    add_column :stores, :uninstalled_at, :datetime
    change_column_null :stores, :access_token, true
  end
end

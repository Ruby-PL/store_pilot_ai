class CreateAiConversationsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_conversations do |t|
      t.references :store, null: false, foreign_key: true
      t.string :title, null: false
      t.timestamps
    end

    create_table :ai_messages do |t|
      t.references :ai_conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.integer :prompt_tokens, null: false, default: 0
      t.integer :completion_tokens, null: false, default: 0
      t.integer :total_tokens, null: false, default: 0
      t.timestamps
    end

    add_index :ai_conversations, [ :store_id, :updated_at ]
  end
end

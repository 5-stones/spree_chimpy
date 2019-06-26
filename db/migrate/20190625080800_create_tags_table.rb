class CreateTagsTable < SpreeExtension::Migration[4.2]
  def change
    create_table :spree_chimpy_tags do |t|
      t.string :name, null: false
      t.integer :external_id, null: false
      t.timestamps
    end
  end
end

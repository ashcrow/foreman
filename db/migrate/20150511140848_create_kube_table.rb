class CreateKubeTable < ActiveRecord::Migration
  def up
    create_table :kubes do |t|
      t.column :cluster, :string, :null => false
      t.belongs_to :hostgroup, index: true, null: false
      t.belongs_to :environment, index: true, null: false
      t.belongs_to :compute_resource, index: false, null: false
      t.column :updated_at, :datetime
      t.column :created_at, :datetime
    end
    add_index :kubes, :cluster
  end

  def down
    drop_table :kubes
  end
end

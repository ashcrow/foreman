

# A description of a Kubernetes cluster
class Kube < ActiveRecord::Base
  belongs_to :hostgroup, dependent: :delete
  belongs_to :environment
  belongs_to :compute_resource
  attr_accessible :cluster, :hostgroup_id, :environment_id, :compute_resource_id, :created_at, :updated_at
  scoped_search :on => [:cluster]

  extend FriendlyId
  friendly_id :cluster

end

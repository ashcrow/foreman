module Api
  module V2
    class KubeController < V2::BaseController
      include Api::Version2

      api :GET, "/kube/", N_("Kubernetes stuff")
      param_group :search_and_pagination, ::Api::V2::BaseController

      def index
        @kubes = resource_scope.paginate(paginate_options)
      end

      api :GET, "/kube/:id", N_("Show a cluster")
      param :id, :identifier, :required => true

      def show
        @kube = Kube.find(params[:id])
      end

      api :DELETE, "/kube/:cluster", N_("Delete a cluster")
      param :cluster, String, :required => true

      def destroy
          # TODO: Actually do stuff with vm's
          cluster = Kube.where('cluster = ?', params[:id]).first
          Hostgroup.where('ancestry = ?', cluster[:hostgroup_id]).each do |hg|
            Host.delete(Host.where('hostgroup_id', hg[:id]))
            Hostgroup.delete(hg[:id])
          end
          Hostgroup.destroy(cluster[:hostgroup_id])
          Kube.destroy(params[:id])
      end

      api :POST, "/kube/", N_("Create a cluster")
      param :cluster, String, :required => true, :desc => 'Name of the cluster'
      param :domain, String, :required => true, :desc => 'Name of the associated domain'
      param :compute_resource, String, :required => true, :desc => 'Name of the compute resource'
      param :environment, String, :required => true, :desc => 'Name of the environment to live in'
      param :nodes, Integer, :required => true, :desc => 'How many nodes to spin up'

      def create
        environment = Environment.where('name = ?', params[:environment]).first
        domain = Domain.where('name = ?', params[:domain]).first
        compute_resource =  ComputeResource.where('name = ?',  params[:compute_resource]).first

        # All in one transaction so we can rollback if there is a problem
        ActiveRecord::Base.transaction do
          # Make the host parent group
          cluster_hostgroup = Hostgroup.new(
             name: params[:cluster],
             environment_id: environment[:id],
             medium_id: 2, # Set to the right one in your testdb
             ptable_id: 8,# Set to the right one in your testdb
             architecture_id: 1,# Set to the right one in your testdb
             operatingsystem_id: 1,# Set to the right one in your testdb
          )
          cluster_hostgroup.save!

          masters_hostgroup = Hostgroup.new(
            name: cluster_hostgroup[:name] + " masters",
            ancestry: cluster_hostgroup[:id].to_s
          )
          masters_hostgroup.save!

          nodes_hostgroup = Hostgroup.new(
            name: cluster_hostgroup[:name] + " nodes",
            ancestry: cluster_hostgroup[:id].to_s
          )
          nodes_hostgroup.save!

          kube = Kube.new(
            cluster: params[:cluster],
            environment_id: environment[:id],
            hostgroup_id: cluster_hostgroup[:id],
            compute_resource_id: compute_resource[:id]
          )
          kube.save!

          master_host = Host.new(
            name: cluster_hostgroup[:name] + "-master",
            hostgroup_id: masters_hostgroup[:id],
            compute_resource_id: compute_resource[:id]
          )
          master_host.save!

          # Create the vm
          vm = compute_resource.create_vm({:name => master_host[:name] + '.' + domain['name']})
          nic = vm.nics.pop
          nic.type = 'network'
          nic.network = 'default'
          vm.nics << nic
          compute_resource.start_vm(vm.identity)

          # FIXME: this passes validation while trying to set it at creation does not
          master_host[:managed] = true
          master_host[:image_id] = 1 # Set to the right one in your testdb
          master_host[:build] = 1
          master_host[:uuid] = vm.identity
          master_host[:provision_method] ='image'
          master_host.save!(:validate => false)

          # Update the Nic
          master_nic = Nic::Managed.where('name = ?', master_host[:name]).first
          master_nic[:domain_id] = domain[:id]
          master_nic[:mac] = vm.mac
          master_nic[:compute_attributes] = HashWithIndifferentAccess.new(
            :type => 'network',
            :network => 'default',
            :bridge => '',
            :model => 'virtio'
          )
          master_nic.save!(:validate => false)
          # Set up host configs
          for n in 1..params[:nodes].to_i do
            host = Host.new(
              name: cluster_hostgroup[:name] + "-node" + n.to_s,
              hostgroup_id: nodes_hostgroup[:id],
              compute_resource_id: compute_resource[:id]
            )
            host.save!
          end
        end
      end
    end
  end
end

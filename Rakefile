require './lib/cluster'
Dir['./lib/tasks/*.rake'].each { |file| load file }

namespace :admin do
  namespace :cluster do
    desc Cluster::RakeDocs.new('admin:cluster:init').desc
    task init: ['cluster:configtest', 'cluster:config_sync_check'] do
      stack = Cluster::Stack.find_or_create

      if Cluster::Base.is_using_efs_storage?
        remote_config = Cluster::RemoteConfig.new
        remote_config.update_efs_server_hostname(Cluster::Filesystem.primary_efs_ip_address)
        remote_config.sync
        Cluster::Stack.update
      end

      puts %Q|Stack "#{stack.name}" initialized, id: #{stack.stack_id}|
      layers = Cluster::Layers.find_or_create
      Cluster::Instances.find_or_create
      Cluster::App.find_or_create
      layers.each do |layer|
        puts %Q|Layer: "#{layer.name}" => #{layer.layer_id}|
        Cluster::Instances.find_in_layer(layer).each do |instance|
          puts %Q|	Instance: #{instance.hostname} => status: #{instance.status}, ec2_instance_id: #{instance.ec2_instance_id}|
        end
      end
      puts
      puts %Q|Initializing the cluster does not start instances. To start them, use "./bin/rake stack:instances:start"|
    end

    desc Cluster::RakeDocs.new('admin:cluster:delete').desc
    task delete: ['cluster:configtest', 'cluster:config_sync_check', 'cluster:production_failsafe'] do
      puts 'deleting app'
      Cluster::App.delete

      puts 'deleting sns topic and subscriptions'
      Cluster::SNS.delete

      puts 'deleting instances'
      Cluster::Instances.delete

      puts 'deleting stack'
      Cluster::Stack.delete

      puts 'deleting instance profile'
      Cluster::InstanceProfile.delete

      puts 'deleting service role'
      Cluster::ServiceRole.delete

      puts 'deleting VPC'
      Cluster::VPC.delete

      puts 'deleting configuration files'
      Cluster::RemoteConfig.new.delete
    end
  end

  namespace :users do
    desc Cluster::RakeDocs.new('admin:users:list').desc
    task list: ['cluster:configtest', 'cluster:config_sync_check'] do
      Cluster::IAMUser.all.each do |user|
        puts %Q|#{user.user_name} => #{user.arn}|
      end
    end
  end

  desc 'create a cluster seed file'
  task create_cluster_seed_file: ['cluster:configtest', 'cluster:config_sync_check', 'cluster:production_failsafe'] do
    recipes = ['mh-opsworks-recipes::stop-matterhorn', 'mh-opsworks-recipes::create-cluster-seed-file']
    layers = ['MySQL db','Admin','Engage','Workers']
    custom_json='{"do_it":true}'

    Cluster::Deployment.execute_chef_recipes_on_layers(
      recipes: recipes,
      layers: layers,
      custom_json: custom_json
    )

    Rake::Task['matterhorn:start'].execute
  end

  desc 'publish a cluster seed file to s3'
  task publish_cluster_seed_file: ['cluster:configtest', 'cluster:config_sync_check', 'cluster:production_failsafe'] do
    asset_bucket_name = Cluster::Base.shared_asset_bucket_name

    a_public_host = Cluster::Instances.online.find do |instance|
      instance.public_dns != nil
    end

    shared_storage_root_path =
      Cluster::Base.stack_custom_json[:storage][:shared_storage_root] ||
      Cluster::Base.stack_custom_json[:storage][:export_root]

    puts shared_storage_root_path

    system %Q|scp -C #{a_public_host.public_dns}:#{shared_storage_root_path}/cluster_seed/cluster_seed.tgz .|

    puts %Q|Uploading cluster_seed.tgz to #{asset_bucket_name}|
    Cluster::Assets.publish_support_asset_to(
      bucket: asset_bucket_name,
      file_name: 'cluster_seed.tgz',
      permissions: 'public'
    )
    puts 'done.'

    File.unlink('cluster_seed.tgz')
  end

  desc 'create and publish a new cluster seed file to s3'
  task create_and_publish_cluster_seed_file: ['cluster:configtest', 'cluster:config_sync_check', 'cluster:production_failsafe'] do
    Rake::Task['admin:create_cluster_seed_file'].execute
    Rake::Task['admin:publish_cluster_seed_file'].execute
  end

  desc Cluster::RakeDocs.new('admin:republish_maven_cache').desc
  task republish_maven_cache: ['cluster:configtest', 'cluster:config_sync_check'] do
    asset_bucket_name = Cluster::Base.shared_asset_bucket_name

    a_public_host = Cluster::Instances.online.find do |instance|
      instance.public_dns != nil
    end

    system %Q|ssh -C #{a_public_host.public_dns} 'sudo bash -c "cd /root && tar cvfz - .m2/"' > maven_cache.tgz|

    puts %Q|Uploading maven_cache.tgz to #{asset_bucket_name}|
    Cluster::Assets.publish_support_asset_to(
      bucket: asset_bucket_name,
      file_name: 'maven_cache.tgz',
      permissions: 'public'
    )
    puts 'done.'

    File.unlink('maven_cache.tgz')
  end
end

task :default do
  Rake.application.tasks.each do |task|
    puts "./bin/rake #{task.name}"
  end
  puts
  puts 'Run "./bin/rake -T" for full task output'
end


namespace :cluster do
  task :production_failsafe do
    config = Cluster::Config.new
    stack_name = config.parsed[:stack][:name]
    if stack_name.match(/prod|prd|stage|stg/i)
      puts
      puts "CAUTION! You've chosen a destructive action that could lead to downtime or permanent data loss."
      puts "Type the full stack name below and hit enter to confirm, or just hit enter to abort."
      puts
      print "CONFIRM: "
      answer = STDIN.gets.strip.chomp

      if answer != stack_name
        exit 1
      end
    end
  end

  desc Cluster::RakeDocs.new('cluster:configtest').desc
  task :configtest do
    config = Cluster::Config.new
    if config.active_config == 'templates/minimal_cluster_config.json'
      puts "\nYou don't have a valid cluster active. You have two options:
* Use 'cluster:switch' to switch into one, or
* Run 'cluster:new' to create and switch into a new one.

"
      exit 1
    end
    config.sane?
  end

  desc Cluster::RakeDocs.new('cluster:active').desc
  task active: [:configtest ] do
    remote_config = Cluster::RemoteConfig.new
    puts %Q|\nCurrently managing: "#{Cluster::Base.stack_config[:name]}" : #{remote_config.active_cluster_config_name}\n|
  end

  desc Cluster::RakeDocs.new('cluster:edit').desc
  task :edit do
    remote_config = Cluster::RemoteConfig.new
    system %Q|$EDITOR #{remote_config.active_cluster_config_name}|

    Rake::Task['cluster:configtest'].execute
    Rake::Task['cluster:config_sync_check'].execute
  end

  desc Cluster::RakeDocs.new('cluster:config_sync_check').desc
  task :config_sync_check do
    remote_config = Cluster::RemoteConfig.new

    config_state = remote_config.config_state
    puts %Q|\nCurrently managing: "#{Cluster::Base.stack_config[:name]}" : #{remote_config.active_cluster_config_name}\n|
    if config_state == :current
      puts "Our local config file is up to date"
    elsif config_state == :behind_remote
      puts "Updating to the latest config file"
      remote_config.download
    else
      puts "\nYour config is ahead of upstream - changes below:\n\n"
      puts remote_config.changeset
      print "Sync these changes and publish to AWS? (y or n): "
      answer = STDIN.gets.strip.chomp

      if ['y','Y'].include?(answer)
        remote_config.sync
        puts 'updating stack attributes. . .'
        Cluster::Stack.update
        puts 'updating app configuration. . .'
        Cluster::App.update
        puts 'updating layer configurations. . .'
        Cluster::Layers.update
      else
        puts "Quitting. Please resolve your config changes and try again."
        exit
      end
    end
  end

  desc Cluster::RakeDocs.new('cluster:console').desc
  task console: [:configtest, :config_sync_check] do
    Cluster::Console.run
  end

  desc Cluster::RakeDocs.new('cluster:reset').desc
  task reset: [:configtest, :config_sync_check, :production_failsafe] do
    recipes = %W|mh-opsworks-recipes::stop-matterhorn
    mh-opsworks-recipes::reset-database
    mh-opsworks-recipes::remove-all-matterhorn-files
    mh-opsworks-recipes::create-matterhorn-directories
    mh-opsworks-recipes::remove-admin-indexes
    mh-opsworks-recipes::remove-engage-indexes|
    layers = ['MySQL db','Admin','Engage','Workers']
    custom_json='{"do_it":true}'

    Cluster::Deployment.execute_chef_recipes_on_layers(
      recipes: recipes,
      layers: layers,
      custom_json: custom_json
    )

    Rake::Task['matterhorn:start'].execute
  end

  desc Cluster::RakeDocs.new('cluster:create_seed_file').desc
  task create_seed_file: [:configtest, :config_sync_check, :production_failsafe] do
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

  desc Cluster::RakeDocs.new('cluster:publish_seed_file').desc
  task publish_seed_file: [:configtest, :config_sync_check, :production_failsafe] do
    asset_bucket_name = Cluster::Base.shared_asset_bucket_name

    a_public_host = Cluster::Instances.online.find do |instance|
      instance.public_dns != nil
    end

    shared_storage_root_path =
      Cluster::Base.stack_custom_json[:storage][:shared_storage_root] ||
      Cluster::Base.stack_custom_json[:storage][:export_root]

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

  desc Cluster::RakeDocs.new('cluster:create_and_publish_seed_file').desc
  task create_and_publish_seed_file: [:configtest, :config_sync_check, :production_failsafe] do
    Rake::Task['cluster:create_seed_file'].execute
    Rake::Task['cluster:publish_seed_file'].execute
  end

  desc Cluster::RakeDocs.new('cluster:apply_seed_file').desc
  task apply_seed_file: [:configtest, :config_sync_check, :production_failsafe] do
    recipes = %W|mh-opsworks-recipes::stop-matterhorn
    mh-opsworks-recipes::reset-database
    mh-opsworks-recipes::remove-all-matterhorn-files
    mh-opsworks-recipes::load-seed-data
    mh-opsworks-recipes::create-matterhorn-directories
    mh-opsworks-recipes::remove-admin-indexes
    mh-opsworks-recipes::remove-engage-indexes|
    layers = ['MySQL db','Admin','Engage','Workers']
    custom_json='{"do_it":true}'

    Cluster::Deployment.execute_chef_recipes_on_layers(
      recipes: recipes,
      layers: layers,
      custom_json: custom_json
    )

    Rake::Task['matterhorn:start'].execute
  end

  desc Cluster::RakeDocs.new('cluster:new').desc
  task :new do
    session = Cluster::ConfigCreationSession.new
    session.choose_variant
    session.get_cluster_name
    session.get_git_url
    session.get_git_revision
    session.compute_cidr_block_root

    if session.zadara_variant?
      session.get_export_root
      session.get_nfs_server_host
    end

    config_file = Cluster::RemoteConfig.create(
      name: session.name,
      variant: session.variant,
      cidr_block_root: session.cidr_block_root,
      app_git_url: session.git_url,
      app_git_revision: session.git_revision,
      export_root: session.export_root,
      nfs_server_host: session.nfs_server_host,
      default_users: JSON.pretty_generate(session.compute_default_users)
    )
    rc_file = Cluster::RcFileSwitcher.new(config_file: config_file)
    rc_file.write

    Cluster::RemoteConfig.new.sync
  end

  desc Cluster::RakeDocs.new('cluster:switch').desc
  task :switch do
    session = Cluster::ClusterSwitcherSession.new

    if ! session.configs.any?
      puts 'No clusters yet.'
      exit
    end

    session.choose_cluster
  end
end

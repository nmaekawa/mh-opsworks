#!/bin/bash

./bin/rake stack:commands:execute_recipes_on_layers \
  layers="MySQL db,Admin,Engage,Workers" \
  recipes="mh-opsworks-recipes::stop-matterhorn,mh-opsworks-recipes::reset-database,mh-opsworks-recipes::remove-all-matterhorn-files,mh-opsworks-recipes::remove-admin-indexes,mh-opsworks-recipes::remove-engage-indexes" \
  custom_json='{"do_it":true}'

./bin/rake matterhorn:start

function(user_config, shard_ids, base_image="")
  local ids_list = std.split(shard_ids, ",");
  local filtered_repos = [
    repo for repo in user_config.repositories
    if std.member(ids_list, repo.id)
  ];
  {
    [field]: user_config[field]
    for field in std.objectFields(user_config)
    if field != "repositories"
  } + { 
    repositories: filtered_repos,
    base_image: if base_image != "" then base_image else user_config.base_image
  }

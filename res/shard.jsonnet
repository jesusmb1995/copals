function(user_config, shard_ids, base_image="")
  local cfg = if std.isFunction(user_config) then user_config() else user_config;
  local ids_list = std.split(shard_ids, ",");
  local filtered_repos = [
    repo for repo in cfg.repositories
    if std.member(ids_list, repo.id)
  ];
  {
    [field]: cfg[field]
    for field in std.objectFields(cfg)
    if field != "repositories"
  } + {
    repositories: filtered_repos,
    base_image: if base_image != "" then base_image else cfg.base_image
  }

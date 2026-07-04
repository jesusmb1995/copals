// Emits bundle metadata: all top-level config fields (base_image, ai_tools, ...)
// except the verbose repositories array, plus a compact repo_ids list of only
// the enabled repos.
function(source_jsonnet)
  {
    [field]: source_jsonnet[field]
    for field in std.objectFields(source_jsonnet)
    if field != "repositories"
  } + {
    repo_ids: [
      r.id
      for r in source_jsonnet.repositories
      if r.enabled == true
    ],
  }

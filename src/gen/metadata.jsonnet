// Emits metadata from the rendered config: top-level fields (minus repositories
// and disabled) plus repo_ids of enabled repos and the disabled map.
function(source_jsonnet)
  {
    [field]: source_jsonnet[field]
    for field in std.objectFields(source_jsonnet)
    if field != 'repositories' && field != 'disabled'
  } + {
    repo_ids: [
      r.id
      for r in source_jsonnet.repositories
      if r.enabled == true
    ],
    disabled: if std.objectHas(source_jsonnet, 'disabled') then source_jsonnet.disabled else {},
  }

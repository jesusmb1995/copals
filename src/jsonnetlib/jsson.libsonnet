// disable_commented(repo, enabled, comment): tag one repo with its enable flag
// and a comment describing the module. Returns { repo: <obj>, disabled: <bool>,
// comment: <string> }. Plain repo objects (not tagged) are enabled by
// process_disabled; tagged ones carry their comment into disabled{}.
{
  disable_commented(repo, enabled, comment):: { repo: repo, disabled: !enabled, comment: comment },

  // disable(repo, cond): dev-only inclusion — [repo] unless cond, else [].
  // Unlike disable_commented, a disabled repo leaves NO trace (not even in
  // disabled{}). Use for pure-dev things prod must not mention.
  // Composes as: process_disabled([...] + j.disable(r.foo, disable_some))
  disable(repo, cond):: if cond then [] else [repo + { enabled: true }],

  // process_disabled(list): pure split of a mixed list into repositories[]
  // (enabled) and disabled{} (keyed by repo id). Items may be plain repo
  // objects (enabled) or disable_commented(...) tags. Disabled entries keep
  // their comment.
  process_disabled(list)::
    {
      repositories: [
        if std.type(t) == 'object' && std.objectHas(t, 'disabled')
        then t.repo + { enabled: true }
        else t + { enabled: true }
        for t in list
        if !(std.type(t) == 'object' && std.objectHas(t, 'disabled') && t.disabled)
      ],
      disabled: {
        [t.repo.id]: t.repo + { enabled: false, comment: t.comment }
        for t in list
        if std.type(t) == 'object' && std.objectHas(t, 'disabled') && t.disabled
      },
    },
}

#!/bin/sh
set -eu

[ $# -ge 1 ] || { echo "usage: gen-apt-wrapper.sh <expected_sources_hash>" >&2; exit 1; }
EXPECTED_SOURCES_HASH="$1"

cat > /usr/local/bin/apt-get << SCRIPT_EOF
#!/bin/sh
EXPECTED_SOURCES_HASH=$EXPECTED_SOURCES_HASH
case "\$1" in
  install)
    for pkg in "\$@"; do
      case "\$pkg" in
        dbus-x11|imagemagick|xdotool|xvfb|libgl1-mesa-dri|libgl1|libegl1|libegl-mesa0)
          exec apt-fast "\$@"
          ;;
      esac
    done
    exec eatmydata apt-fast "\$@"
    ;;
  update)
    SOURCES_HASH=\$(sha256sum /etc/apt/sources.list | cut -d" " -f1)
    # Also re-update when the package lists are gone (e.g. pruned cache
    # volume) even if sources.list is unchanged.
    if [ "\$SOURCES_HASH" = "\$EXPECTED_SOURCES_HASH" ] && ls /var/lib/apt/lists/*Packages* >/dev/null 2>&1; then
      echo "apt-get update: skipped (sources.list unchanged)"
    else
      EXPECTED_SOURCES_HASH=\$SOURCES_HASH
      exec eatmydata apt-fast "\$@"
    fi
    ;;
  remove|purge|autoremove|upgrade|full-upgrade|search|show|list|clean|autoclean)
    exec eatmydata apt-fast "\$@"
    ;;
  *)
    exec /usr/bin/apt-get "\$@"
    ;;
esac
SCRIPT_EOF

chmod +x /usr/local/bin/apt-get

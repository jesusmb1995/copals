#!/bin/sh
set -e
out_dir="${1:-vendor}"

for cmd in curl sha256sum tar xz unzip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: required command '$cmd' not found in PATH" >&2
        exit 1
    fi
done

fetch_and_install() {
    url="$1"
    expected_hash="$2"
    binary_name="$3"
    target_dir="${4:-.}"
    output_name="${5:-}"

    effective_name="${output_name:-$(basename "${binary_name}")}"
    if [ -e "${target_dir}/${effective_name}" ]; then
        echo "Skipping ${effective_name} (already present)"
        return 0
    fi

    base=$(basename "${url}")
    tmp_dir=$(mktemp -d)
    tmp_tar="${tmp_dir}/${base}"

    echo "Downloading ${binary_name}"
    curl -fSL# "$url" -o "$tmp_tar"
    echo "$expected_hash  $tmp_tar" | sha256sum -c -

    case "$base" in
        *.tar.gz|*.tgz|*.apk)  tar xzf "$tmp_tar" -C "$tmp_dir" ;;
        *.tar.xz|*.txz)  tar xJf "$tmp_tar" -C "$tmp_dir" ;;
        *.zip)           unzip -q "$tmp_tar" -d "$tmp_dir" ;;
        *)                                ;;
    esac

    tmp_bin="$tmp_dir/$binary_name"
    chmod +x "$tmp_bin"
    real_name=$(basename "$tmp_bin")
    mv "$tmp_bin" "$target_dir/$real_name"
    if [ -n "$output_name" ] && [ "$output_name" != "$real_name" ]; then
        ln -sf "$real_name" "$target_dir/$output_name"
    fi
    rm -rf "$tmp_dir" "$tmp_tar"
}

# like fetch_and_install but for debian .deb packages: extracts the embedded
# data.tar.* (xz or gz) after unpacking the ar wrapper. glibc target only.
fetch_and_install_from_deb_url() {
    url="$1"
    expected_hash="$2"
    binary_name="$3"
    target_dir="${4:-.}"
    output_name="${5:-}"

    effective_name="${output_name:-$(basename "${binary_name}")}"
    if [ -e "${target_dir}/${effective_name}" ]; then
        echo "Skipping ${effective_name} (already present)"
        return 0
    fi

    if ! command -v ar >/dev/null 2>&1; then
        echo "error: 'ar' (binutils) required to extract .deb: ${url}" >&2
        exit 1
    fi

    base=$(basename "${url}")
    tmp_dir=$(mktemp -d)
    tmp_deb="${tmp_dir}/${base}"

    echo "Downloading ${binary_name}"
    curl -fSL# "$url" -o "$tmp_deb"
    echo "$expected_hash  $tmp_deb" | sha256sum -c -

    ( cd "$tmp_dir" && ar x "$base" )
    case "$(ls "$tmp_dir"/data.tar.* 2>/dev/null)" in
        *.xz)  tar xJf "$tmp_dir"/data.tar.xz  -C "$tmp_dir" ;;
        *.gz)  tar xzf "$tmp_dir"/data.tar.gz  -C "$tmp_dir" ;;
        *.zst) ( cd "$tmp_dir" && tar --zstd -xf data.tar.zst ) ;;
    esac

    tmp_bin="$tmp_dir/$binary_name"
    chmod +x "$tmp_bin"
    real_name=$(basename "$tmp_bin")
    mv "$tmp_bin" "$target_dir/$real_name"
    if [ -n "$output_name" ] && [ "$output_name" != "$real_name" ]; then
        ln -sf "$real_name" "$target_dir/$output_name"
    fi
    rm -rf "$tmp_dir"
}

mkdir -p "${out_dir}"

fetch_and_install \
    "https://github.com/google/go-jsonnet/releases/download/v0.22.0/go-jsonnet_0.22.0_linux_amd64.tar.gz" \
    "e87a93ea44e34da92c15636205c7f2240bf3ac92d00ccb855dbb4e7e03ea6941" \
    "jsonnet" \
    "${out_dir}"

fetch_and_install \
    "https://github.com/mitsuhiko/minijinja/releases/download/2.21.0/minijinja-cli-x86_64-unknown-linux-musl.tar.xz" \
    "d2c91c46739f7e41b8666d877a65881c180f81011890da9229d2a4b1e1991b2f" \
    "minijinja-cli-x86_64-unknown-linux-musl/minijinja-cli" \
    "${out_dir}" \
    "j2"

fetch_and_install \
    "https://github.com/amber-lang/amber/releases/download/0.6.0-alpha/amber-linux-musl-x86_64.tar.xz" \
    "14062fdc6f1652ed8c1230c24f912e23a78a3bb7e8ae396790019e4f02cbc9f5" \
    "amber" \
    "${out_dir}"

fetch_and_install \
    "https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64" \
    "b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f" \
    "jq-linux-amd64" \
    "${out_dir}" \
    "jq"

fetch_and_install_jsonschema_gnu() {
fetch_and_install \
    "https://github.com/sourcemeta/jsonschema/releases/download/v16.0.0/jsonschema-16.0.0-linux-x86_64.zip" \
    "c9083e65cd4160b06b63f927c4547c5607ab64318fc0a73616f7ecbab72ed708" \
    "jsonschema-16.0.0-linux-x86_64/bin/jsonschema" \
    "${out_dir}"
}

fetch_and_install_jsonschema_musl() {
fetch_and_install \
    "https://github.com/sourcemeta/jsonschema/releases/download/v16.0.0/jsonschema-16.0.0-linux-x86_64-musl.zip" \
    "aeb239523c5a7b657adff1dac7182272d714d653e17ba9b44ac702bd3d23390c" \
    "jsonschema-16.0.0-linux-x86_64-musl/bin/jsonschema" \
    "${out_dir}"
}

# lua: native spec-file loading for the nvim plugin pre-fetch hook.
# glibc target extracts the debian snapshot .deb; musl target reuses
# fetch_and_install on the alpine .apk (gzip tar).
fetch_and_install_lua_gnu() {
fetch_and_install_from_deb_url \
    "https://snapshot.debian.org/archive/debian/20260101T000000Z/pool/main/l/lua5.4/lua5.4_5.4.7-1+b2_amd64.deb" \
    "da5947f8274bdcd0dd6d1aaf6d780bc7537827455d456d07dc9c14daf702f1df" \
    "usr/bin/lua5.4" \
    "${out_dir}" \
    "lua"
}

fetch_and_install_lua_musl() {
fetch_and_install \
    "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/lua5.4-5.4.7-r0.apk" \
    "130a2726f461f90661176452b42ad28b6fada86af78da13aeef5ded591964d6a" \
    "usr/bin/lua5.4" \
    "${out_dir}" \
    ".lua-real"
if [ ! -e "${out_dir}/lua" ]; then
    cat > "${out_dir}/lua" << 'WRAPPER'
#!/bin/sh
dir=$(dirname "$0")
export LD_LIBRARY_PATH="${dir}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export VENDOR_DIR="${dir}"
exec "${dir}/.lua-real" "$@"
WRAPPER
    chmod +x "${out_dir}/lua"
fi

# lua5.4-libs → liblua-5.4.so.0.0.0 + soname symlink
fetch_and_install \
    "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/lua5.4-libs-5.4.7-r0.apk" \
    "2788121cf38d6b1869974e26cc337d9ffc207a6e74cb8866d96444ded05705c7" \
    "usr/lib/lua5.4/liblua-5.4.so.0.0.0" \
    "${out_dir}"
ln -sf "liblua-5.4.so.0.0.0" "${out_dir}/liblua-5.4.so.0"

# readline → libreadline.so.8.2 + soname symlink
fetch_and_install \
    "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/readline-8.2.13-r1.apk" \
    "520fa586c689144928191bee13e2c85ff4e170ad87d1471ec48e3e97611673d8" \
    "usr/lib/libreadline.so.8.2" \
    "${out_dir}"
ln -sf "libreadline.so.8.2" "${out_dir}/libreadline.so.8"

# libncursesw → libncursesw.so.6.5 + soname symlink
fetch_and_install \
    "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/libncursesw-6.5_p20250503-r0.apk" \
    "aeafdfca68147b014705b4e2564639ade6345198debb522f2c6c51d32e417651" \
    "usr/lib/libncursesw.so.6.5" \
    "${out_dir}"
ln -sf "libncursesw.so.6.5" "${out_dir}/libncursesw.so.6"
}


# linked standard library (non-static)
case "$(ls /lib/ 2>/dev/null)" 
  in *musl*) 
    fetch_and_install_jsonschema_musl
    fetch_and_install_lua_musl
    ;; 
  *)
    fetch_and_install_jsonschema_gnu
    fetch_and_install_lua_gnu
    ;; 
esac

# produces {out_dir}/lib/bashunit
(
  cd "${out_dir}"
  bash bashunit_installer/install_bashunit.sh 
  mv bashunit_installer/lib .
)

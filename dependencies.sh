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
        *.tar.gz|*.tgz)  tar xzf "$tmp_tar" -C "$tmp_dir" ;;
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
    "https://github.com/sourcemeta/jsonschema/releases/download/continuous/jsonschema-16.0.0-54fa2425-linux-x86_64.zip" \
    "b4957acc123a9b0738a4873ab2a49fe5191cbe1b7bbb62755590418289b51e44" \
    "jsonschema-16.0.0-54fa2425-linux-x86_64/bin/jsonschema" \
    "${out_dir}"
}

fetch_and_install_jsonschema_musl() {
fetch_and_install \
    "https://github.com/sourcemeta/jsonschema/releases/download/continuous/jsonschema-16.0.0-54fa2425-linux-x86_64-musl.zip" \
    "f929e52b5423146adc22b106a8693ccc6d2956330694ec596a36b184468bc5b7" \
    "jsonschema-16.0.0-54fa2425-linux-x86_64-musl/bin/jsonschema" \
    "${out_dir}"
}


# linked standard library (non-static)
case "$(ls /lib/ 2>/dev/null)" 
  in *musl*) 
    fetch_and_install_jsonschema_musl 
    ;; 
  *)
    fetch_and_install_jsonschema_gnu
    ;; 
esac

# produces {out_dir}/lib/bashunit
(
  cd "${out_dir}"
  bash bashunit_installer/install_bashunit.sh 
  mv bashunit_installer/lib .
)

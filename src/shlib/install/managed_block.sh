#!/usr/bin/env bash
# Written in [Amber](https://amber-lang.com/)
# version: 0.6.0-alpha
[ "$EUID" -ne 0 ] && { { command -v sudo >/dev/null 2>&1 && __sudo=sudo; } || { command -v doas >/dev/null 2>&1 && __sudo=doas; }; }
if [ -n "$ZSH_VERSION" ]; then
    EXEC_SHELL="zsh"
    IFS='.' read -A EXEC_SHELL_VERSION <<< "$ZSH_VERSION"
elif [ -n "$KSH_VERSION" ]; then
    EXEC_SHELL="ksh"
    __exec_shell_version="${.sh.version##*/}"
    IFS='.' read -a EXEC_SHELL_VERSION <<< "${__exec_shell_version%% *}"
else
    EXEC_SHELL="bash"
    EXEC_SHELL_VERSION=("${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" "${BASH_VERSINFO[2]}")
fi
# replace(source: Text, search: Text, replace: Text)
replace__0_v0() {
    local source_59="${1}"
    local search_60="${2}"
    local replace_61="${3}"
    # Here we use a command to avoid #646
    local result_62=""
    left_comp=("${EXEC_SHELL_VERSION[@]}")
    right_comp=(4 3)
    local comp
    comp="$(
        # Compare if left array >= right array
        len_comp="$( (( "${#left_comp[@]}" < "${#right_comp[@]}" )) && echo "${#left_comp[@]}"|| echo "${#right_comp[@]}")"
        for (( i=0; i<len_comp; i++ )); do
            left="${left_comp[i]?"Index out of bounds (at unknown)"}"
            right="${right_comp[i]?"Index out of bounds (at unknown)"}"
            if (( "${left}" > "${right}" )); then
                echo 1
                exit
            elif (( "${left}" < "${right}" )); then
                echo 0
                exit
            fi
        done
        (( "${#left_comp[@]}" == "${#right_comp[@]}" || "${#left_comp[@]}" > "${#right_comp[@]}" )) && echo 1 || echo 0
)"
    if [ "$(( $([ "_${EXEC_SHELL}" != "_ksh" ]; echo $?) || $(( $([ "_${EXEC_SHELL}" != "_bash" ]; echo $?) && comp )) ))" != 0 ]; then
        result_62="${source_59//"${search_60}"/"${replace_61}"}"
        __status=$?
    else
        result_62="${source_59//"${search_60}"/${replace_61}}"
        __status=$?
    fi
    ret_replace0_v0="${result_62}"
    return 0
}

__SED_VERSION_UNKNOWN_0=0
__SED_VERSION_GNU_1=1
__SED_VERSION_BUSYBOX_2=2
# sed_version()
sed_version__2_v0() {
    # We can't match against a word "GNU" because
    # alpine's busybox sed returns "This is not GNU sed version"
    re='Copyright.+Free Software Foundation'; [[ $(sed --version 2>/dev/null) =~ $re ]]
    __status=$?
    if [ "$(( __status == 0 ))" != 0 ]; then
        ret_sed_version2_v0="${__SED_VERSION_GNU_1}"
        return 0
    fi
    # On BSD single `sed` waits for stdin. We must use `sed --help` to avoid this.
    re='BusyBox'; [[ $(sed --help 2>&1) =~ $re ]]
    __status=$?
    if [ "$(( __status == 0 ))" != 0 ]; then
        ret_sed_version2_v0="${__SED_VERSION_BUSYBOX_2}"
        return 0
    fi
    ret_sed_version2_v0="${__SED_VERSION_UNKNOWN_0}"
    return 0
}

# replace_regex(source: Text, search: Text, replace_text: Text, extended: Bool)
replace_regex__3_v0() {
    local source_54="${1}"
    local search_55="${2}"
    local replace_text_56="${3}"
    local extended_57="${4}"
    sed_version__2_v0 
    local sed_version_58="${ret_sed_version2_v0}"
    replace__0_v0 "${search_55}" "/" "\\/"
    search_55="${ret_replace0_v0}"
    replace__0_v0 "${replace_text_56}" "/" "\\/"
    replace_text_56="${ret_replace0_v0}"
    if [ "$(( $(( sed_version_58 == __SED_VERSION_GNU_1 )) || $(( sed_version_58 == __SED_VERSION_BUSYBOX_2 )) ))" != 0 ]; then
        # '\b' is supported but not in POSIX standards. Disable it
        replace__0_v0 "${search_55}" "\\b" "\\\\b"
        search_55="${ret_replace0_v0}"
    fi
    if [ "${extended_57}" != 0 ]; then
        # GNU sed versions 4.0 through 4.2 support extended regex syntax,
        # but only via the "-r" option
        if [ "$(( sed_version_58 == __SED_VERSION_GNU_1 ))" != 0 ]; then
            local command_1
            command_1="$(sed -r -e "s/${search_55}/${replace_text_56}/g" <<<"${source_54}")"
            __status=$?
            ret_replace_regex3_v0="${command_1}"
            return 0
        else
            local command_2
            command_2="$(sed -E -e "s/${search_55}/${replace_text_56}/g" <<<"${source_54}")"
            __status=$?
            ret_replace_regex3_v0="${command_2}"
            return 0
        fi
    else
        if [ "$(( $(( sed_version_58 == __SED_VERSION_GNU_1 )) || $(( sed_version_58 == __SED_VERSION_BUSYBOX_2 )) ))" != 0 ]; then
            # GNU Sed BRE handle \| as a metacharacter, but it is not POSIX standands. Disable it
            replace__0_v0 "${search_55}" "\\|" "|"
            search_55="${ret_replace0_v0}"
        fi
        local command_3
        command_3="$(sed -e "s/${search_55}/${replace_text_56}/g" <<<"${source_54}")"
        __status=$?
        ret_replace_regex3_v0="${command_3}"
        return 0
    fi
}

# dir_exists(path: Text)
dir_exists__38_v0() {
    local path_71="${1}"
    [ -d "${path_71}" ]
    __status=$?
    ret_dir_exists38_v0="$(( __status == 0 ))"
    return 0
}

# file_exists(path: Text)
file_exists__39_v0() {
    local path_52="${1}"
    [ -f "${path_52}" ]
    __status=$?
    ret_file_exists39_v0="$(( __status == 0 ))"
    return 0
}

# _project_root()
_project_root__171_v0() {
    file_exists__39_v0 "src/copals.ab"
    local ret_file_exists39_v0__5_8="${ret_file_exists39_v0}"
    if [ "${ret_file_exists39_v0__5_8}" != 0 ]; then
        local pwd_val_53="$PWD"
        replace_regex__3_v0 "${pwd_val_53}" "/[^/]+\$" "" 1
        ret__project_root171_v0="${ret_replace_regex3_v0}"
        return 0
    fi
    ret__project_root171_v0="$PWD"
    return 0
}

_project_root__171_v0 
__PROJECT_ROOT_63="${ret__project_root171_v0}"
project_vendor_64="${__PROJECT_ROOT_63}/copals/vendor"
installed_vendor_65="/usr/lib/copals/vendor"
# The installed vendor dir is authoritative when copals runs inside its own
# container: the host repo is bind-mounted at the same absolute path, so the
# project vendor dir also "exists" but its tools are only populated inside the
# image. Prefer the installed tree whenever it actually holds the binaries.
# resolve_vendor_dir()
resolve_vendor_dir__172_v0() {
    dir_exists__38_v0 "${installed_vendor_65}"
    local ret_dir_exists38_v0__21_8="${ret_dir_exists38_v0}"
    file_exists__39_v0 "${installed_vendor_65}/jsonnet"
    local ret_file_exists39_v0__21_41="${ret_file_exists39_v0}"
    if [ "$(( ret_dir_exists38_v0__21_8 && ret_file_exists39_v0__21_41 ))" != 0 ]; then
        ret_resolve_vendor_dir172_v0="${installed_vendor_65}"
        return 0
    fi
    dir_exists__38_v0 "${project_vendor_64}"
    local ret_dir_exists38_v0__24_8="${ret_dir_exists38_v0}"
    file_exists__39_v0 "${project_vendor_64}/jsonnet"
    local ret_file_exists39_v0__24_39="${ret_file_exists39_v0}"
    if [ "$(( ret_dir_exists38_v0__24_8 && ret_file_exists39_v0__24_39 ))" != 0 ]; then
        ret_resolve_vendor_dir172_v0="${project_vendor_64}"
        return 0
    fi
    dir_exists__38_v0 "${installed_vendor_65}"
    local ret_dir_exists38_v0__27_8="${ret_dir_exists38_v0}"
    if [ "${ret_dir_exists38_v0__27_8}" != 0 ]; then
        ret_resolve_vendor_dir172_v0="${installed_vendor_65}"
        return 0
    fi
    dir_exists__38_v0 "${project_vendor_64}"
    local ret_dir_exists38_v0__30_8="${ret_dir_exists38_v0}"
    if [ "${ret_dir_exists38_v0__30_8}" != 0 ]; then
        ret_resolve_vendor_dir172_v0="${project_vendor_64}"
        return 0
    fi
    ret_resolve_vendor_dir172_v0=""
    return 0
}

resolve_vendor_dir__172_v0 
__VENDOR_DIR_72="${ret_resolve_vendor_dir172_v0}"
# jq_resolve()
jq_resolve__173_v0() {
    if [ "$([ "_${__VENDOR_DIR_72}" != "_" ]; echo $?)" != 0 ]; then
        ret_jq_resolve173_v0="jq"
        return 0
    fi
    ret_jq_resolve173_v0="${__VENDOR_DIR_72}/jq"
    return 0
}

# j2_resolve()
j2_resolve__174_v0() {
    if [ "$([ "_${__VENDOR_DIR_72}" != "_" ]; echo $?)" != 0 ]; then
        ret_j2_resolve174_v0="j2"
        return 0
    fi
    ret_j2_resolve174_v0="${__VENDOR_DIR_72}/j2"
    return 0
}

# jsonnet_resolve()
jsonnet_resolve__175_v0() {
    if [ "$([ "_${__VENDOR_DIR_72}" != "_" ]; echo $?)" != 0 ]; then
        ret_jsonnet_resolve175_v0="jsonnet"
        return 0
    fi
    ret_jsonnet_resolve175_v0="${__VENDOR_DIR_72}/jsonnet"
    return 0
}

# jsonschema_resolve()
jsonschema_resolve__176_v0() {
    if [ "$([ "_${__VENDOR_DIR_72}" != "_" ]; echo $?)" != 0 ]; then
        ret_jsonschema_resolve176_v0="jsonschema"
        return 0
    fi
    ret_jsonschema_resolve176_v0="${__VENDOR_DIR_72}/jsonschema"
    return 0
}

# lua_resolve()
lua_resolve__177_v0() {
    if [ "$([ "_${__VENDOR_DIR_72}" != "_" ]; echo $?)" != 0 ]; then
        ret_lua_resolve177_v0="lua"
        return 0
    fi
    ret_lua_resolve177_v0="${__VENDOR_DIR_72}/lua"
    return 0
}

jq_resolve__173_v0 
j2_resolve__174_v0 
jsonnet_resolve__175_v0 
jsonschema_resolve__176_v0 
lua_resolve__177_v0 
# Inverse of rm_if_feature_not: remove rel_path when features[feature] == expected
# (defaults to "" so an unset feature never triggers removal). Use to drop GUI
# artifacts in pure-TTY presets, e.g. mode == "tmux".
# Marker lines wrapping the bundle-managed block. Plain ASCII with no glob/regex
# metacharacters, so exact line-equality matching (==) stays stable across runs.
# The "___DEVTOOLS_AUTOGEN___" token scopes this installer's block; other tools'
# managed blocks (nvm, pyenv, pathman, ...) are left untouched.
# Trim trailing empty strings off a line list (keeps internal blank lines).
# Drop every managed block (BEGIN..END inclusive) from a line list. A BEGIN with
# no matching END drops from BEGIN to EOF (treated as malformed/abandoned).
# Refresh the managed block in `dest` (absolute path) so it contains exactly the
# shipped `src` content, wrapped in MANAGED_BEGIN/MANAGED_END. Merge-safe and
# idempotent: user content outside the block is preserved verbatim; re-running
# replaces the block instead of duplicating it. If `dest` is absent it is
# created holding just the block. Reusable for any source/dest pair.

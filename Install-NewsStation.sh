#!/usr/bin/env bash

set -Eeuo pipefail

resolve_downloads_dir() {
    local candidate=""

    case "$(uname -s)" in
        Darwin)
            printf '%s' "${HOME}/Downloads"
            ;;
        Linux)
            if command -v xdg-user-dir >/dev/null 2>&1; then
                candidate="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"
            fi

            if [[ -n "${candidate}" && "${candidate}" != "${HOME}" ]]; then
                printf '%s' "${candidate}"
            elif [[ -d "${HOME}/Pobrane" ]]; then
                printf '%s' "${HOME}/Pobrane"
            else
                printf '%s' "${HOME}/Downloads"
            fi
            ;;
        *)
            printf '%s' "${HOME}/Downloads"
            ;;
    esac
}

readonly NEWSSTATION_OWNER="ScopCony"
readonly NEWSSTATION_REPO="newsstation-backend"
readonly NEWSSTATION_BRANCH="main"
readonly NEWSSTATION_UV_VERSION="0.11.32"
readonly NEWSSTATION_BOOTSTRAP_URL="https://raw.githubusercontent.com/ScopCony/newsstation-launcher/main/Install-NewsStation.sh"
readonly NEWSSTATION_API="https://api.github.com/repos/${NEWSSTATION_OWNER}/${NEWSSTATION_REPO}"
readonly NEWSSTATION_TOKEN_URL="https://github.com/settings/personal-access-tokens/new?name=NewsStation&description=Odczyt+prywatnego+repozytorium+NewsStation&target_name=${NEWSSTATION_OWNER}&expires_in=none&contents=read"
readonly NEWSSTATION_DOWNLOADS="$(resolve_downloads_dir)"
readonly NEWSSTATION_HOME="${NEWSSTATION_DOWNLOADS}/NewsStation"
readonly NEWSSTATION_VERSIONS="${NEWSSTATION_HOME}/versions"
readonly NEWSSTATION_TOOLS="${NEWSSTATION_HOME}/tools"
readonly NEWSSTATION_CONFIG="${NEWSSTATION_HOME}/environment"
readonly NEWSSTATION_CURRENT="${NEWSSTATION_HOME}/current.sha"
readonly NEWSSTATION_LAUNCHER="${NEWSSTATION_HOME}/launcher.sh"
readonly NEWSSTATION_LINUX_SECRETS="${NEWSSTATION_HOME}/secrets.env"
readonly NEWSSTATION_UV="${NEWSSTATION_TOOLS}/uv"

fail() {
    printf '\nBłąd: %s\n' "$1" >&2
    exit 1
}

info() {
    printf '%s\n' "$1"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Brak wymaganego polecenia: $1"
}

current_os() {
    case "$(uname -s)" in
        Darwin) printf 'macos' ;;
        Linux) printf 'linux' ;;
        *) fail "Ten starter obsługuje macOS i Linux. Na Windows użyj polecenia PowerShell." ;;
    esac
}

read_environment() {
    if [[ -f "${NEWSSTATION_CONFIG}" ]]; then
        tr -d '[:space:]' < "${NEWSSTATION_CONFIG}"
    fi
}

save_environment() {
    printf '%s\n' "$1" > "${NEWSSTATION_CONFIG}"
    chmod 600 "${NEWSSTATION_CONFIG}"
}

ask_environment_once() {
    local detected selected choice
    detected="$(current_os)"
    selected="$(read_environment)"

    if [[ -n "${selected}" ]]; then
        [[ "${selected}" == "${detected}" ]] || fail \
            "Zapamiętane środowisko (${selected}) nie pasuje do tego komputera (${detected})."
        printf '%s' "${selected}"
        return
    fi

    info "" >&2
    info "NewsStation — pierwsze uruchomienie" >&2
    info "Wybierz środowisko:" >&2
    info "  1. macOS" >&2
    info "  2. Linux (Bazzite, CachyOS i inne)" >&2
    printf 'Numer środowiska: ' >&2
    read -r choice

    case "${choice}" in
        1) selected="macos" ;;
        2) selected="linux" ;;
        *) fail "Nieprawidłowy wybór środowiska." ;;
    esac

    [[ "${selected}" == "${detected}" ]] || fail \
        "Wybrano ${selected}, ale wykryto ${detected}. Uruchom starter ponownie i wybierz właściwy system."

    save_environment "${selected}"
    printf '%s' "${selected}"
}

keychain_get() {
    security find-generic-password -a "${USER}" -s "$1" -w 2>/dev/null || true
}

keychain_set() {
    security add-generic-password -U -a "${USER}" -s "$1" -w "$2" >/dev/null
}

linux_secret_get() {
    local name="$1"
    [[ -f "${NEWSSTATION_LINUX_SECRETS}" ]] || return 0
    sed -n "s/^${name}=//p" "${NEWSSTATION_LINUX_SECRETS}" | head -n 1
}

linux_secret_set() {
    local name="$1" value="$2" temp_file
    temp_file="$(mktemp "${NEWSSTATION_HOME}/secrets.XXXXXX")"

    if [[ -f "${NEWSSTATION_LINUX_SECRETS}" ]]; then
        grep -v "^${name}=" "${NEWSSTATION_LINUX_SECRETS}" > "${temp_file}" || true
    fi
    printf '%s=%s\n' "${name}" "${value}" >> "${temp_file}"
    chmod 600 "${temp_file}"
    mv -f -- "${temp_file}" "${NEWSSTATION_LINUX_SECRETS}"
}

secret_get() {
    local environment="$1" name="$2"
    if [[ "${environment}" == "macos" ]]; then
        keychain_get "NewsStation ${name}"
    else
        linux_secret_get "${name}"
    fi
}

secret_set() {
    local environment="$1" name="$2" value="$3"
    if [[ "${environment}" == "macos" ]]; then
        keychain_set "NewsStation ${name}" "${value}"
    else
        linux_secret_set "${name}" "${value}"
    fi
}

open_github_token_page_if_needed() {
    local environment="$1"
    [[ -z "$(secret_get "${environment}" "GITHUB_TOKEN")" ]] || return 0

    info "" >&2
    info "Potrzebny jest token GitHuba tylko do odczytu." >&2
    info "Otwieram stronę tworzenia tokenu w przeglądarce..." >&2

    if [[ "${environment}" == "macos" ]]; then
        open "${NEWSSTATION_TOKEN_URL}" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then
        (xdg-open "${NEWSSTATION_TOKEN_URL}" >/dev/null 2>&1 || true) &
    fi

    info "Na stronie GitHuba ustaw:" >&2
    info "  1. Repository access: Only select repositories" >&2
    info "  2. Selected repositories: newsstation-backend" >&2
    info "  3. Repository permissions > Contents: Read-only" >&2
    info "  4. Kliknij Generate token i skopiuj token." >&2
    info "Jeśli przeglądarka się nie otworzyła, użyj adresu:" >&2
    info "${NEWSSTATION_TOKEN_URL}" >&2
    info "" >&2
}

read_masked_secret() {
    local value="" character

    while IFS= read -r -s -n 1 character; do
        if [[ -z "${character}" ]]; then
            break
        fi

        case "${character}" in
            $'\177'|$'\b')
                if [[ -n "${value}" ]]; then
                    value="${value%?}"
                    printf '\b \b' >&2
                fi
                ;;
            *)
                value+="${character}"
                printf '*' >&2
                ;;
        esac
    done

    printf '\n' >&2
    printf '%s' "${value}"
}

ask_secret() {
    local environment="$1" name="$2" label="$3" hidden="${4:-yes}" value
    value="$(secret_get "${environment}" "${name}")"
    if [[ -n "${value}" ]]; then
        printf '%s' "${value}"
        return
    fi

    if [[ "${hidden}" == "yes" ]]; then
        printf '%s: ' "${label}" >&2
        value="$(read_masked_secret)"
    else
        printf '%s: ' "${label}" >&2
        read -r value
    fi
    [[ -n "${value}" ]] || fail "Nie podano wartości: ${label}"
    [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || fail \
        "Wartość ${label} zawiera niedozwolony znak końca linii."
    secret_set "${environment}" "${name}" "${value}"
    printf '%s' "${value}"
}

github_request() {
    local token="$1" url="$2"
    curl --fail --silent --show-error --location \
        --connect-timeout 10 --max-time 30 \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${token}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${url}"
}

latest_commit_sha() {
    local token="$1" response sha
    response="$(github_request "${token}" "${NEWSSTATION_API}/commits/${NEWSSTATION_BRANCH}")" || return 1
    sha="$(printf '%s' "${response}" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' | head -n 1)"
    [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || return 1
    printf '%s' "${sha}"
}

version_ready() {
    local sha="$1" version_dir
    [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || return 1
    version_dir="${NEWSSTATION_VERSIONS}/${sha}"
    [[ -f "${version_dir}/.newsstation-ready" && \
       -f "${version_dir}/main.py" && \
       -x "${version_dir}/.venv/bin/python" ]]
}

download_version() {
    local token="$1" sha="$2" version_dir archive
    version_dir="${NEWSSTATION_VERSIONS}/${sha}"

    if version_ready "${sha}"; then
        printf '%s' "${version_dir}"
        return
    fi

    archive="$(mktemp "${NEWSSTATION_HOME}/download.XXXXXX.tar.gz")"

    info "Pobieram nową wersję programu..." >&2
    github_request "${token}" "${NEWSSTATION_API}/tarball/${sha}" > "${archive}" || \
        fail "Nie udało się pobrać programu z prywatnego repozytorium."

    if tar -tzf "${archive}" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
        fail "Archiwum programu zawiera niebezpieczną ścieżkę."
    fi

    mkdir -p "${version_dir}"
    tar -xzf "${archive}" --strip-components=1 -C "${version_dir}"
    rm -f -- "${archive}"
    [[ -f "${version_dir}/main.py" && -f "${version_dir}/requirements.txt" ]] || \
        fail "Pobrana paczka nie zawiera kompletnego programu."
    printf '%s' "${version_dir}"
}

ensure_uv() {
    if [[ -x "${NEWSSTATION_UV}" ]]; then
        return
    fi

    info "Przygotowuję środowisko uruchomieniowe..." >&2
    mkdir -p "${NEWSSTATION_TOOLS}"
    curl -LsSf "https://astral.sh/uv/${NEWSSTATION_UV_VERSION}/install.sh" | \
        env UV_UNMANAGED_INSTALL="${NEWSSTATION_TOOLS}" UV_NO_MODIFY_PATH=1 sh >/dev/null
    [[ -x "${NEWSSTATION_UV}" ]] || fail "Nie udało się przygotować narzędzia uv."
}

prepare_version() {
    local version_dir="$1" python_path
    python_path="${version_dir}/.venv/bin/python"

    if [[ ! -x "${python_path}" ]]; then
        "${NEWSSTATION_UV}" venv --python 3.12 "${version_dir}/.venv" || \
            fail "Nie udało się utworzyć środowiska Pythona."
    fi
    "${NEWSSTATION_UV}" pip sync --python "${python_path}" "${version_dir}/requirements.txt" || \
        fail "Nie udało się zainstalować zależności programu."
    touch "${version_dir}/.newsstation-ready" || \
        fail "Nie udało się oznaczyć wersji jako gotowej."
}

save_current_sha() {
    local sha="$1" temp_file
    temp_file="$(mktemp "${NEWSSTATION_HOME}/current.XXXXXX")"
    printf '%s\n' "${sha}" > "${temp_file}"
    chmod 600 "${temp_file}"
    mv -f -- "${temp_file}" "${NEWSSTATION_CURRENT}"
}

read_current_sha() {
    if [[ -f "${NEWSSTATION_CURRENT}" ]]; then
        tr -d '[:space:]' < "${NEWSSTATION_CURRENT}"
    fi
}

save_local_launcher() {
    local temp_launcher
    temp_launcher="$(mktemp "${NEWSSTATION_HOME}/launcher.XXXXXX")"
    if curl -fsSL --connect-timeout 10 --max-time 30 \
        "${NEWSSTATION_BOOTSTRAP_URL}" -o "${temp_launcher}"; then
        chmod 700 "${temp_launcher}"
        mv -f -- "${temp_launcher}" "${NEWSSTATION_LAUNCHER}"
    fi
}

run_version() {
    local environment="$1" version_dir="$2" google_key supabase_url supabase_key
    shift 2
    google_key="$(ask_secret "${environment}" "GOOGLE_API_KEY" "Klucz Google AI Studio")"
    supabase_url="$(ask_secret "${environment}" "SUPABASE_URL" "Adres Supabase" no)"
    supabase_key="$(ask_secret "${environment}" "SUPABASE_SERVICE_KEY" "Klucz serwerowy Supabase")"

    export GOOGLE_API_KEY="${google_key}"
    export SUPABASE_URL="${supabase_url}"
    export SUPABASE_SERVICE_KEY="${supabase_key}"
    export PYTHONUNBUFFERED=1

    info ""
    info "Uruchamiam NewsStation..."
    cd "${version_dir}"
    "${version_dir}/.venv/bin/python" main.py "$@"
}

main() {
    local environment github_token latest_sha current_sha version_dir
    umask 077
    require_command curl
    require_command tar
    mkdir -p "${NEWSSTATION_HOME}" "${NEWSSTATION_VERSIONS}" "${NEWSSTATION_TOOLS}"

    environment="$(ask_environment_once)"
    if [[ "${environment}" == "macos" ]]; then
        require_command security
    fi

    save_local_launcher || true
    open_github_token_page_if_needed "${environment}"
    github_token="$(ask_secret "${environment}" "GITHUB_TOKEN" "Token GitHuba tylko do odczytu")"
    current_sha="$(read_current_sha)"
    if [[ -n "${current_sha}" && ! "${current_sha}" =~ ^[0-9a-f]{40}$ ]]; then
        current_sha=""
    fi

    if latest_sha="$(latest_commit_sha "${github_token}")"; then
        if [[ "${latest_sha}" == "${current_sha}" ]] && version_ready "${current_sha}"; then
            info "Lokalna kopia programu jest aktualna."
        else
            if (
                version_dir="$(download_version "${github_token}" "${latest_sha}")"
                ensure_uv
                prepare_version "${version_dir}"
                save_current_sha "${latest_sha}"
            ); then
                current_sha="${latest_sha}"
                info "Nowa wersja programu jest gotowa."
            elif [[ -n "${current_sha}" ]] && version_ready "${current_sha}"; then
                info "Aktualizacja nie powiodła się. Uruchamiam ostatnią działającą kopię."
            else
                fail "Nie udało się przygotować programu i nie ma lokalnej działającej kopii."
            fi
        fi
    else
        if [[ -n "${current_sha}" ]] && version_ready "${current_sha}"; then
            info "Nie udało się sprawdzić GitHuba. Uruchamiam ostatnią działającą kopię."
        else
            fail "Nie udało się połączyć z prywatnym repozytorium i nie ma lokalnej kopii programu."
        fi
    fi

    version_dir="${NEWSSTATION_VERSIONS}/${current_sha}"
    version_ready "${current_sha}" || fail "Nie można odnaleźć gotowej lokalnej kopii programu."
    run_version "${environment}" "${version_dir}" "$@"
}

main "$@"

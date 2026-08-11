#!/usr/bin/env bash
#
# hitomatito dotfiles — instalador para Arch Linux / CachyOS
# Dotfiles installer for Arch Linux / CachyOS
#
# Uso / Usage:
#   ./install.sh                 # interactivo / interactive
#   ./install.sh --lang es       # idioma forzado / force language
#   ./install.sh --lang en
#   ./install.sh --no-packages   # solo copiar configs / configs only
#   ./install.sh --no-config     # solo paquetes / packages only
#   ./install.sh --no-aur        # no usar paru/yay para paquetes AUR
#   ./install.sh --dry-run       # simular sin tocar nada / simulate only
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuración / Settings
# ---------------------------------------------------------------------------
LANG_CODE="auto"
INSTALL_PACKAGES=true
INSTALL_CONFIGS=true
USE_AUR=true
DRY_RUN=false
AUR_HELPER=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

# Paquetes requeridos / Required packages
REQUIRED_PACKAGES=(
  # Hyprland ecosystem
  hyprland hyprlock hyprpaper hyprsunset hyprpolkitagent quickshell
  # Terminales y shell / terminals & shell
  kitty foot ghostty fish fastfetch nano
  # Utilidades de escritorio / desktop utilities
  cliphist wl-clipboard grim slurp brightnessctl playerctl wireplumber
  pavucontrol networkmanager network-manager-applet blueberry rfkill swaylock
  yazi python entr rsync
  # Menús y apps (AUR en Arch, repo cachyos en CachyOS)
  tofi zen-browser-bin obsidian
)

# ---------------------------------------------------------------------------
# Colores / Colors
# ---------------------------------------------------------------------------
C_RESET="\e[0m"
C_INFO="\e[1;36m"
C_OK="\e[1;32m"
C_WARN="\e[1;33m"
C_ERR="\e[1;31m"
C_BOLD="\e[1m"

# ---------------------------------------------------------------------------
# Mensajería bilingüe / Bilingual messages
# ---------------------------------------------------------------------------
info()  { if [ "${LANG_CODE}" = "es" ]; then printf "%b%s%b\n" "$C_INFO"  ":: ${1:-}" "$C_RESET"; else printf "%b%s%b\n" "$C_INFO"  ":: ${2:-${1:-}}" "$C_RESET"; fi; }
ok()    { if [ "${LANG_CODE}" = "es" ]; then printf "%b%s%b\n" "$C_OK"    "   ✓ ${1:-}" "$C_RESET"; else printf "%b%s%b\n" "$C_OK"    "   ✓ ${2:-${1:-}}" "$C_RESET"; fi; }
warn()  { if [ "${LANG_CODE}" = "es" ]; then printf "%b%s%b\n" "$C_WARN"  "   ⚠ ${1:-}" "$C_RESET"; else printf "%b%s%b\n" "$C_WARN"  "   ⚠ ${2:-${1:-}}" "$C_RESET"; fi; }
err()   { if [ "${LANG_CODE}" = "es" ]; then printf "%b%s%b\n" "$C_ERR"   "!! ${1:-}" "$C_RESET"; else printf "%b%s%b\n" "$C_ERR"   "!! ${2:-${1:-}}" "$C_RESET"; fi; }

# ---------------------------------------------------------------------------
# Argumentos / Arguments
# ---------------------------------------------------------------------------
usage() {
    printf "%s\n" "Uso / Usage:"
    printf "%s\n" "  ./install.sh [--lang es|en] [--no-packages] [--no-config] [--no-aur] [--dry-run]"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lang)        LANG_CODE="$2"; shift 2 ;;
        --no-packages) INSTALL_PACKAGES=false; shift ;;
        --no-config)   INSTALL_CONFIGS=false; shift ;;
        --no-aur)      USE_AUR=false; shift ;;
        --dry-run)     DRY_RUN=true; shift ;;
        -h|--help)     usage ;;
        *) err "Argumento desconocido / Unknown argument: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Detectar idioma / Detect language
# ---------------------------------------------------------------------------
detect_lang() {
    if [ "${LANG_CODE}" = "auto" ]; then
        case "${LANG:-${LC_ALL:-}}" in
            es_*|es-*) LANG_CODE="es" ;;
            *)         LANG_CODE="en" ;;
        esac
    fi
    if [ "${LANG_CODE}" != "es" ] && [ "${LANG_CODE}" != "en" ]; then
        printf "%s\n" "Select language / Selecciona idioma:"
        printf "%s\n" "  1) English"
        printf "%s\n" "  2) Español"
        read -r -p "> " choice
        case "$choice" in
            1) LANG_CODE="en" ;;
            2) LANG_CODE="es" ;;
            *) LANG_CODE="en" ;;
        esac
    fi
}

# ---------------------------------------------------------------------------
# Detectar distribución / Detect distribution
# ---------------------------------------------------------------------------
DISTRO_ID=""
DISTRO_NAME=""
detect_distro() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-}"
        DISTRO_NAME="${NAME:-}"
    fi
    case "$DISTRO_ID" in
        arch|cachyos) : ;;
        "")
            err "No se pudo detectar la distribución. / Could not detect distribution."
            exit 1
            ;;
        *)
            warn "Distribución no oficialmente soportada ($DISTRO_NAME). Continuando de todos modos. / Not officially supported, continuing anyway."
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Detectar helper AUR / Detect AUR helper
# ---------------------------------------------------------------------------
detect_aur_helper() {
    if [ "${USE_AUR}" = false ]; then
        AUR_HELPER=""
        return
    fi
    if command -v paru >/dev/null 2>&1; then
        AUR_HELPER="paru"
    elif command -v yay >/dev/null 2>&1; then
        AUR_HELPER="yay"
    else
        AUR_HELPER=""
    fi
}

# ---------------------------------------------------------------------------
# Paquetes / Packages
# ---------------------------------------------------------------------------
install_packages() {
    [ "${INSTALL_PACKAGES}" = true ] || return 0
    [ "${DRY_RUN}" = true ] && { info "Se instalarían los paquetes / Would install packages: ${REQUIRED_PACKAGES[*]}"; return 0; }

    info "Comprobando paquetes… / Checking packages…"

    local to_pacman=() to_aur=() missing=()
    local pkg

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if pacman -Q "$pkg" >/dev/null 2>&1; then
            continue  # ya instalado / already installed
        fi
        if pacman -Si "$pkg" >/dev/null 2>&1; then
            to_pacman+=("$pkg")
        elif [ -n "${AUR_HELPER}" ]; then
            to_aur+=("$pkg")
        else
            missing+=("$pkg")
        fi
    done

    # --- Paquetes de repos oficiales / Official repository packages ---
    if [ ${#to_pacman[@]} -gt 0 ]; then
        info "Paquetes oficiales a instalar / Official packages to install:"
        printf "   %s\n" "${to_pacman[@]}"
        if [ "${DRY_RUN}" = true ]; then return 0; fi
        read -r -p "¿Instalar con sudo pacman? / Install with sudo pacman? [y/N] " ans
        if [[ "${ans,,}" =~ ^(y|yes)$ ]]; then
            sudo pacman -S --needed --noconfirm "${to_pacman[@]}" || true
        else
            warn "Omitidos por elección del usuario / Skipped by user choice."
            missing+=("${to_pacman[@]}")
        fi
    fi

    # --- Paquetes AUR ---
    if [ ${#to_aur[@]} -gt 0 ]; then
        info "Paquetes AUR a instalar con $AUR_HELPER / AUR packages to install with $AUR_HELPER:"
        printf "   %s\n" "${to_aur[@]}"
        read -r -p "¿Continuar? / Continue? [y/N] " ans
        if [[ "${ans,,}" =~ ^(y|yes)$ ]]; then
            "${AUR_HELPER}" -S --needed --noconfirm "${to_aur[@]}" || true
        else
            warn "Omitidos por elección del usuario / Skipped by user choice."
            missing+=("${to_aur[@]}")
        fi
    fi

    # --- Verificación final / Final verification ---
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! pacman -Q "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        warn "Paquetes que quedaron pendientes / Packages still missing:"
        printf "   %s\n" "${missing[@]}"
    fi
}

# ---------------------------------------------------------------------------
# Configs / Configs
# ---------------------------------------------------------------------------
CONFIG_DIRS=(hypr kitty tofi fish fastfetch foot ghostty quickshell swaylock)
CONFIG_SINGLE=(nano/nanorc)

backup_existing() {
    local dest="$1"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        local bak="${dest}.bak-${TS}"
        if [ "${DRY_RUN}" = true ]; then
            info "(simulado) Backup de $dest a $bak / (dry-run) Backup $dest to $bak"
        else
            mv "$dest" "$bak"
            ok "Backup: $dest → $bak"
        fi
    fi
}

copy_configs() {
    [ "${INSTALL_CONFIGS}" = true ] || return 0

    info "Copiando configs a ~/.config… / Copying configs to ~/.config…"

    mkdir -p "$HOME/.config"

    for dir in "${CONFIG_DIRS[@]}"; do
        if [ ! -d "${SCRIPT_DIR}/${dir}" ]; then
            warn "Directorio ${dir} no encontrado en el repo / not found in repo."
            continue
        fi
        dest="$HOME/.config/${dir}"
        backup_existing "$dest"
        if [ "${DRY_RUN}" = true ]; then
            info "(simulado) copiar ${dir}/ → ${dest}/ / (dry-run) copy"
        else
            mkdir -p "$dest"
            cp -a "${SCRIPT_DIR}/${dir}/." "$dest/"
            ok "Config ${dir} instalada / installed."
        fi
    done

    # Archivos individuales / Single files
    for file in "${CONFIG_SINGLE[@]}"; do
        [ -f "${SCRIPT_DIR}/${file}" ] || continue
        dest="$HOME/.${file##*/}"  # nano/nanorc → ~/.nanorc
        backup_existing "$dest"
        if [ "${DRY_RUN}" = true ]; then
            info "(simulado) copiar ${file} → ${dest} / (dry-run) copy"
        else
            cp -a "${SCRIPT_DIR}/${file}" "$dest"
            ok "Config ${file} instalada / installed."
        fi
    done
}

install_bin_scripts() {
    [ "${INSTALL_CONFIGS}" = true ] || return 0
    [ -d "${SCRIPT_DIR}/bin" ] || return 0

    info "Instalando scripts en ~/.local/bin… / Installing scripts to ~/.local/bin…"
    if [ "${DRY_RUN}" = true ]; then
        info "(simulado) copiar bin/ → ~/.local/bin/ / (dry-run) copy"
        return 0
    fi
    mkdir -p "$HOME/.local/bin"
    cp -a "${SCRIPT_DIR}/bin/." "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/notify" "$HOME/.local/bin/"*.sh 2>/dev/null || true
    ok "Scripts instalados en ~/.local/bin / Scripts installed."
}

install_applications() {
    [ "${INSTALL_CONFIGS}" = true ] || return 0
    [ -d "${SCRIPT_DIR}/applications" ] || return 0

    info "Instalando entradas de aplicación (.desktop)… / Installing application entries…"
    if [ "${DRY_RUN}" = true ]; then
        info "(simulado) copiar applications/ → ~/.local/share/applications/ / (dry-run) copy"
        return 0
    fi
    mkdir -p "$HOME/.local/share/applications"
    cp -a "${SCRIPT_DIR}/applications/." "$HOME/.local/share/applications/"
    ok "Entradas .desktop instaladas / .desktop entries installed."
}

# ---------------------------------------------------------------------------
# Validación del dotfile / Dotfile validation
# ---------------------------------------------------------------------------
validate_configs() {
    info "Validando configs / Validating configs…"

    # Sintaxis Lua / Lua syntax (valida los archivos del repo / validates repo files)
    if command -v luac >/dev/null 2>&1; then
        local lua_files=("${SCRIPT_DIR}/hypr/hyprland.lua")
        lua_files+=("${SCRIPT_DIR}"/hypr/lua/*.lua)
        if luac -p "${lua_files[@]}" 2>/dev/null; then
            ok "Sintaxis Lua válida / Lua syntax OK."
        else
            warn "Problema de sintaxis Lua (revisa los mensajes arriba) / Lua syntax issue (see above)."
        fi
    fi

    # zeditor (binario personal del usuario / user's own binary)
    if ! command -v zeditor >/dev/null 2>&1; then
        warn "'zeditor' no está en el PATH. Los botones de 'Notas' del control center no abrirán nada hasta que lo instales o lo renombres en quickshell/shell.qml. / 'zeditor' is not in PATH. The 'Notes' buttons in the control center won't work until you install it or rename it in quickshell/shell.qml."
    else
        ok "'zeditor' encontrado en el PATH / found in PATH."
    fi
}

# ---------------------------------------------------------------------------
# Resumen final / Final summary
# ---------------------------------------------------------------------------
final_summary() {
    printf "\n%b===========================================%b\n" "$C_OK" "$C_RESET"
    if [ "${LANG_CODE}" = "es" ]; then
        printf "%bInstalación completada / Installation completed%b\n\n" "$C_BOLD" "$C_RESET"
        printf "Siguientes pasos / Next steps:\n"
        printf "  1. Cierra sesión y vuelve a entrar (o reinicia).\n"
        printf "  2. Selecciona la sesión Hyprland en tu gestor de pantalla.\n"
        printf "  3. El primer arranque genera theme.lua y el wallpaper automáticamente (switch_theme.sh minimal).\n"
        printf "  4. Si algo no va bien: hyprctl reload; logs en ~/.local/state/hypr/.\n"
        printf "  5. Para sincronizar cambios: bin/ricesync (requiere 'entr').\n"
    else
        printf "%bInstallation completed%b\n\n" "$C_BOLD" "$C_RESET"
        printf "Next steps:\n"
        printf "  1. Log out and log back in (or reboot).\n"
        printf "  2. Pick the Hyprland session in your display manager.\n"
        printf "  3. On first start, theme.lua and the wallpaper are generated automatically (switch_theme.sh minimal).\n"
        printf "  4. If something is off: hyprctl reload; logs in ~/.local/state/hypr/.\n"
        printf "  5. To sync future changes: bin/ricesync (requires 'entr').\n"
    fi
    printf "%b===========================================%b\n" "$C_OK" "$C_RESET"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    detect_lang
    detect_distro
    detect_aur_helper

    printf "%b===========================================%b\n" "$C_INFO" "$C_RESET"
    if [ "${LANG_CODE}" = "es" ]; then
        printf "%bInstalador de dotfiles — %s%b\n" "$C_BOLD" "$DISTRO_NAME" "$C_RESET"
    else
        printf "%bDotfiles installer — %s%b\n" "$C_BOLD" "$DISTRO_NAME" "$C_RESET"
    fi
    printf "Repo: %s\n" "${SCRIPT_DIR}"
    [ -n "${AUR_HELPER}" ] && printf "AUR helper: %s\n" "${AUR_HELPER}"
    [ "${DRY_RUN}" = true ] && printf "%bMODO SIMULACIÓN / DRY-RUN%b\n" "$C_WARN" "$C_RESET"
    printf "%b===========================================%b\n" "$C_INFO" "$C_RESET"
    printf "\n"

    install_packages
    copy_configs
    install_bin_scripts
    install_applications
    validate_configs
    final_summary
}

main "$@"

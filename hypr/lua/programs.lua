local programs = {}

-- Resolvemos el home del usuario real: los dotfiles funcionan para cualquier usuario
local home = os.getenv("HOME")
local bin = home .. "/.local/bin"

programs.terminal = "footclient"
programs.fileManager = "footclient yazi"
programs.menu = bin .. "/smart_menu.sh"
programs.bar = "quickshell"
programs.screenshot = 'grim -g "$(slurp)" - | wl-copy'
programs.browser = "zen-browser"
programs.powermenu = bin .. "/smart_powermenu.sh"
programs.lock = "hyprlock"
programs.note = "obsidian"
programs.dock = ""

-- Utilidades locales del usuario
programs.smartClipboard = bin .. "/smart_clipboard.sh"
programs.smartControlCenter = bin .. "/smart_controlcenter.sh"
programs.smartTheme = bin .. "/smart_theme.sh"
programs.smartVolume = bin .. "/smart_volume.sh"
programs.smartBrightness = bin .. "/smart_brightness.sh"
programs.spotifyRestart = bin .. "/spotify_restart.sh"
programs.switchTheme = home .. "/.config/hypr/scripts/switch_theme.sh"

return programs

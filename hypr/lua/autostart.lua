local programs = require("lua.programs")

hl.on("hyprland.start", function ()
  hl.exec_cmd("foot --server")

  local zenBgRule = hl.window_rule({
      name = "zen-background-startup",
      match = { class = "zen" },
      workspace = "special:zenbg silent"
  })

  hl.timer(function()
      hl.exec_cmd(programs.browser)
      hl.timer(function()
          zenBgRule:set_enabled(false)
      end, { timeout = 5000, type = "oneshot" })
  end, { timeout = 2000, type = "oneshot" })

  hl.exec_cmd("hyprpaper")
  hl.exec_cmd(programs.bar)
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("nm-applet --indicator")
  hl.exec_cmd("systemctl --user start hyprpolkitagent")
  hl.exec_cmd("hyprsunset -t 5000")
  hl.exec_cmd(programs.switchTheme .. " minimal")
  hl.exec_cmd("sh -c 'cliphist list | tail -n +501 | cliphist delete'")
end)

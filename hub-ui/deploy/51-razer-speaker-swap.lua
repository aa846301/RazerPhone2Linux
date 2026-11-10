-- Razer Phone 2 hub orientation (landscape, earpiece end on the LEFT): the amp fed by the ALSA left slot sits at the
-- bottom end, i.e. on the viewer's RIGHT. Swap the speaker sink's channel map so FL/FR match what the viewer sees.
-- Verified by listening on 2026-11-10 (left-only tone came from the right). WirePlumber 0.4 (Lua config).
-- Install: ~/.config/wireplumber/main.lua.d/51-razer-speaker-swap.lua, then restart wireplumber.
table.insert(alsa_monitor.rules, {
  matches = { { { "node.name", "matches", "alsa_output.*" } } },
  apply_properties = { ["audio.position"] = "FR,FL" },
})

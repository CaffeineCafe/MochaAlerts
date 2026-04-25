# MochaAlerts

A World of Warcraft addon that plays voice and sound alerts when your tracked spells and items come off cooldown and are ready to cast.

**Author:** CaffeineCafe  
**Version:** 1.3.2  
**Interface:** 120005 (Midnight 12.0.5)

---

## Features

- **Text-to-Speech (TTS) alerts** — WoW's built-in TTS engine speaks the spell or item name when it's ready
- **Sound effect alerts** — choose from 20+ Blizzard UI sounds or 60+ WeakAuras-style sound effects per spell/item
- **Visual on-screen alerts** — animated text and icon overlay with configurable position and scale
- **Per-alert flyout customization** — click a tracked spell or item to open a dedicated side panel for icon selection, positioning, scaling, and display options
- **Independent icon/text placement** — unlink icon and text so they can be positioned and scaled separately anywhere on screen
- **Unlock & Drag placement mode** — dimmed full-screen placement overlay lets you drag icon and text directly and fine-tune them with sliders
- **Per-spell customization** — set a custom TTS phrase, custom on-screen text, toggle the icon and text, or enable a double-alert repeat
- **Health Potion grouping** — all health pot variants share one alert entry so you're never spammed
- **Fleeting potion grouping** — cauldron variants and their base potions are merged into one entry automatically
- **Spell override support** — correctly handles talent overrides and form transforms (e.g. Void Meta / Annihilation)
- **GCD-immune alerting** — alerts are never delayed by the global cooldown; interrupt-like spells (e.g. Disrupt) are auto-detected and gated on the real lockout CD
- **Configurable alert color** — change the on-screen alert text color via the built-in color picker
- **Lockout suppression** — suppresses false alerts triggered by movement abilities like Roll and Lighter Than Air
- **Configurable poll interval** — adjust how frequently the addon checks for cooldown changes (0.01s–0.40s) for snappier or lighter alerts
- **Minimap button** — left-click to open settings; drag to reposition around the minimap
- **No dependencies** — no external libraries required

---

## Installation

1. Download and extract the `MochaAlerts` folder.
2. Place it in: `World of Warcraft\_retail_\Interface\AddOns\MochaAlerts\`
3. Launch WoW and enable the addon in the character select screen.

---

## Getting Started

Open the config panel with **/malerts** or by clicking the minimap icon.

**Adding spells:**
- Shift-click a spell directly from your spellbook while the config panel is open — it populates the Add box automatically.
- Type a spell name or numeric spell ID into the Add box and click **Add** (or press Enter).

**Adding items (trinkets, potions):**
- Shift-click an item from your bags while the config panel is open.
- Type an item name or numeric item ID into the Add box.
- Click **Scan Trinkets** to auto-detect equipped trinkets with use effects.

---

## Config Panel

| Control | Description |
|---|---|
| Enable alerts | Master on/off toggle for all alerts |
| Alert during combat | Allow alerts to fire while in combat |
| Unlock / Lock | Enable dragging the alert frame to a new position |
| Reset | Return the alert frame to its default position |
| Alert scale | Resize the alert overlay (50% – 200%) |
| Poll interval | Adjust how frequently the addon polls for cooldown changes (0.01s – 0.40s) |
| TTS Voice | Cycle through available TTS voices; plays a preview on selection |
| Test Alert | Fire a test voice alert |
| Add spell or item | Input box to add by name, ID, or shift-click link |
| Scan Trinkets | Auto-add equipped trinkets with use effects |

### Spell / Item Row Buttons

Each tracked entry has a row of buttons on the right side:

| Button | Description |
|---|---|
| Sound dropdown | Choose **TTS**, **None** (visual only), or a sound effect |
| **>** | Preview the configured alert for this entry |
| Icon button | Toggle the spell/item icon on the alert frame |
| **T** | Toggle the alert text label on/off |
| **x2** | Repeat the alert a second time after 1.5 seconds |
| **Tt** | Set a custom on-screen text override for this alert |
| **X** | Remove this spell or item from tracking |

When **TTS** mode is selected, a text box appears below the row where you can type a custom phrase (e.g. `"Chaos Strike"` instead of the default `"Annihilation ready"`). Leave it blank to use the default spell name.

### Per-Alert Customization Panel

Click the alert icon in a tracked row to open the customization flyout.

| Control | Description |
|---|---|
| Current Mode | Shows whether icon and text are currently linked or unlinked |
| Switch To Unlinked / Linked | Toggle between shared placement and independent placement |
| Unlock & Drag | Open the dimmed full-screen placement mode for screen-based positioning |
| Icon Picker | Choose a custom icon from the built-in searchable icon library |
| Icon X / Y / Scale | Adjust icon placement and size when unlinked |
| Text X / Y / Scale | Adjust text placement and size when unlinked |

When unlinked, the icon and text use screen-based positions that are separate from the base alert anchor.

### Unlock & Drag Mode

Unlock & Drag opens a dimmed full-screen overlay where you can:

- Drag the icon anywhere on screen
- Drag the text anywhere on screen
- Fine-tune icon and text X/Y/scale with sliders inside the overlay
- Keep those placements fully separate from the base alert frame position

---

## Slash Commands

| Command | Description |
|---|---|
| `/malerts` | Open the config panel |
| `/malerts add [name or ID]` | Track a spell or item |
| `/malerts remove [name or ID]` | Stop tracking a spell or item |
| `/malerts list` | Print all tracked spells and items with their cooldown state |
| `/malerts scantrinkets` | Auto-add equipped trinkets with use effects |
| `/malerts toggle` | Enable or disable all alerts |
| `/malerts on` / `/malerts off` | Explicitly enable or disable alerts |
| `/malerts test` | Fire a test voice alert |
| `/malerts test [name or ID]` | Fire a test alert for a specific spell |
| `/malerts voice` | List available TTS voices |
| `/malerts voice [index]` | Select a TTS voice by index (e.g. `/malerts voice 1`) |
| `/malerts power` | Show current resource level and any resource threshold settings |
| `/malerts debug` | Toggle debug output (prints alert events and state changes to chat) |
| `/malerts tts` | Run full TTS diagnostic (requires debug mode) |
| `/malerts reset` | Reset all account-wide settings to defaults |

---

## Saved Variables

| Variable | Scope | Contents |
|---|---|---|
| `MochaAlertsDB` | Account-wide | Global settings: enabled, alert in combat, visual alert on/off, alert scale, alert position, TTS voice index |
| `MochaAlertsCharDB` | Per-character | Tracked spells and items (including all per-spell customizations) |

---

## Sound Library

MochaAlerts includes 60+ sound effects (sourced from the WeakAuras community sound pack) plus 20 Blizzard UI sounds selectable per spell/item:

**Blizzard sounds include:** Raid Warning, Ready Check, Alarm Clock, Level Up, Quest Complete, Map Ping, PVP Queue Ready, and more.

**Custom sounds include:** Air Horn, Batman Punch, Temple Bell, Warning Siren, Roaring Lion, Tada Fanfare, and many more.

---

## Tips

- Spells are stored **per character** — your Demon Hunter's tracked spells won't appear on your Monk.
- The addon suppresses alerts on zone changes, resurrections, and form transitions to avoid false positives.
- If TTS isn't working, make sure **Text-to-Speech** is enabled in WoW's Accessibility settings and a voice is selected.
- Use `/malerts debug` to troubleshoot alert timing or suppression behavior.

---

## Contact

Questions or feedback? Stop by: **twitch.tv/caffeinecafe**

---

## Support

If you found MochaAlerts useful, consider buying me a coffee! ☕

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-caffeinecafe-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/caffeinecafe)

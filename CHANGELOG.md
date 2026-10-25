# RestedXP Guides

## Unreleased (local fork)

- Added the **Transparent** theme: the guide HUD keeps its fonts, colours and
  progress accents but drops the filled background and border art, so it draws
  straight over the game world.
- Added a **Font Shadow** toggle under Look and Feel. The Transparent theme
  enables a 1-pixel drop shadow by default; the toggle overrides it for any
  theme. Uses the 3.3.5a `SetShadowColor`/`SetShadowOffset` FontString API.
- Settings, tool and report windows stay opaque so they remain readable;
  tips, targeting/item panels and level splits follow the theme.
- Backdrops are now rebuilt on every theme change, so switching away from
  Transparent restores the previous border art.

## [v4.8.25](https://github.com/RestedXP/RXPGuides/tree/v4.8.25) (2025-11-08)
[Full Changelog](https://github.com/RestedXP/RXPGuides/compare/v4.8.24...v4.8.25) [Previous Releases](https://github.com/RestedXP/RXPGuides/releases)

- Remove 'stats' infix for non-weapon tooltips  
    mostly leftover debugging  
- Update budget AH scanner display  
    EP/c too small to be meaningful at most levels, match format of BiS  
- Fixed issue with quest completion checks  
- Fixed quest issue with quest completion checks  
- Remove ItemUpgrades TRAINER\_SHOW event  
    Obsolete logic, armor types are level calculated now  
- Update Active Target placeholders  
- Exclude emergency action flashing when dead  

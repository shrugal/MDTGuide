Version 1.06
- Added `zoom` command to scale minimum and maximum zoom 
- Changed command parameters a bit

Version 1.05
- Added smooth transitions between pulls
- Added option to fade out window when mouse isn't over it
- Speed up route estimation by adding a min-heap for the path queue as well as length and weight limits
- Improved route estimation accuracy by switching weights to a rolling average
- Fixed switching sublevels manually in guide mode

Version 1.04
- Updated toc version for patch 9.0.5
- Added button to zoom to current pull
- Added button to announce selected or selected and following pulls
- Vastly improved route estimation performance by doing a deep search inside enemy groups

Version 1.03
- Keep zoom level between certain min and max values if possible
- Try to get previous and next pulls into the view if possible
- Take dungeon map scale into account when zooming
- Streamlined overall zoom calculation
- Hull drawing fix should work for all dungeons now

Version 1.02
- Made addon work with alternative MDT addons
- Added "/mdtg height" command and restored resizer in guide mode to change window size
- Adjusted zoom behavior a bit
- Fixed hull-line width and distance to enemy groups on the map
- Fixed breaking dev-mode
- Added missing starting locations for route prediction in Shadowlands dungeons

Version 1.01
- Updated TOC version for patch 9.0.2

Version 1
- Added `/mdtg` chat command to toggle route estimation
- Added experimental route estimation based on shortest path through killed enemies, toggle with `/mdtg route`
- Fixed enemy info frame in guide mode
- Fixed problems after MDT renaming

Version 1-beta3
- Updated TOC version for 8.3

Version 1-beta2
- Added coloring current pull cyan
- Properly handle bosses
- Bugfixes and refinements

Version 1-beta1
- Initial release
- Added compact view for MDT
- Added zooming to selected pull
- Added automatically zooming to current/next pull based on enemy forces
- Added coloring dead enemies red

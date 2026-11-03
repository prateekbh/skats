# Analytics

The web build sends anonymous gameplay events to Google Analytics 4 so we can see how people
play. Nothing is collected on desktop builds, in autotests or in CI, and the page skips
analytics entirely when the browser sends **Do Not Track**. No personal data is sent: only the
events below (GA4's own standard web measurement also applies on the hosted page).

- The gtag snippet and the `window.skTrack` bridge live in `web/shell.html` (forks: replace the
  measurement ID `G-2Y4QBD4HGN` there).
- `scripts/autoload/analytics.gd` (`Analytics.track(event, params)`) sends the game's events.
  Run any test with `--analytics-log` to print events instead of sending them.
- Missions record funnel steps with `milestone("step_name")` (see `Mission.milestone`).

## The player journey

| Step | Event | Useful parameters |
|---|---|---|
| Page opens, game loads | `game_loaded`, `launcher_shown` | `load_ms` |
| Looks around the menu | `controls_opened`, `settings_opened`, `setting_changed` | `name`, `value` |
| Picks a stage | `episode_selected` | `episode_id`, `attempt`, `best_score` |
| Opening story | `comic_started`, `comic_finished` | `strip`, `seconds`, `skipped` |
| Hatch launch | `launch_skipped` | `at_s` |
| Takes the controls | `mission_started` | `episode_id`, `attempt`, `screen`, `touch` |
| Progress in the mission | `milestone` | `step` (`wave_1_cleared`, `wave_2_cleared`, `boss_started`, `shield_proven`, `scramblers_armed`, `shield_down`, `boss_destroyed`), `mission_s`, `hull`, `score` |
| Weapon use | `special_fired` | `weapon`, `ammo_left`, `mission_s` |
| Stops mid-fight | `pause` | `mission_s`, `last_milestone` |
| Result | `mission_end` | `result` (win/lose), `reason`, `mission_s`, `score`, `kills`, `accuracy`, `hull`, `rank`, `last_milestone`, `specials_fired`, `attempt` |
| What next | `retry`, `quit_to_menu` | `from` (pause/debrief), `next_attempt` |
| Touch devices | `touch_mode_on`, `portrait_shown`, `portrait_pause`, `fullscreen_clicked` | `last_state` |
| Closes the tab | `game_exit` | `last_state` (e.g. `playing:ep01`, `debrief:ep01`) |

Every event also carries `session_s` (seconds since the game loaded).

## Reading it in GA4

GA4 only reports custom parameters you register: in Admin > Custom definitions, add event-scoped
dimensions for `episode_id`, `step`, `last_milestone`, `result`, `reason`, `weapon`, `strip`,
`attempt`, `last_state`, `rank` and metrics for `mission_s`, `score`, `accuracy`, `load_ms`.
Then build a funnel: `episode_selected` > `mission_started` > `milestone` (`wave_1_cleared` >
`wave_2_cleared` > `boss_started` > `shield_proven` > `shield_down` > `boss_destroyed`) > `mission_end` (win).
Where `mission_end` shows `lose`, `last_milestone` says how far people got before failing.

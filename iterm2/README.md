# iTerm2

Version-controlled iTerm2 config. iTerm keeps its live config in a binary plist
(`~/Library/Preferences/com.googlecode.iterm2.plist`); these files are the
reproducible backups.

## Files
- **`iTerm2 State.itermexport`** — full-state export (all app settings: Exclude
  from Dock, startup policy, keybindings, appearance… *and* the profiles).
  **Restore:** iTerm2 → Settings → General → **Import** (or open the file).
- **`profiles.json`** — human-readable, profiles-only export (mocha/latte
  dual-mode, Hack Nerd Font, floating Alt+Enter hotkey, No Title Bar, Cmd+Enter
  disabled). **Restore:** Profiles → Other Actions → **Import JSON Profiles**.
  Redundant with the full export, kept because it's diffable/reviewable.

## Refresh the backups after changing settings in iTerm
```sh
# profiles only (readable):
plutil -extract 'New Bookmarks' json -o - \
  ~/Library/Preferences/com.googlecode.iterm2.plist | jq '{Profiles: .}' > profiles.json
# full state: iTerm2 → Settings → General → Export  (overwrite "iTerm2 State.itermexport")
```

## Notes
- The `.itermexport` is a gzipped bundle (not diffable) and also packs session
  state / the AI chat db, so re-exporting churns it — that's expected.
- Do **not** symlink profiles into `DynamicProfiles/` — iTerm materializes GUI
  edits back into prefs with the same Guid and breaks the profile. Import instead.

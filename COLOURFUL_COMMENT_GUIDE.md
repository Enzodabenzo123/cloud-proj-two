# Colourful comment guide — for video walkthrough narration

## Why this exists
When you're screen-recording and narrating, you need to find the exact line
that proves each rubric point *while you're talking*, not scroll around
looking for it. This guide defines a small, consistent comment tagging
system so those spots are visually unmissable in the editor — and gives
Claude Code exact instructions for where to apply each tag.

## Prerequisite: install the "Better Comments" extension
These tags only render in colour if the editor has an extension that knows
to color them. The standard one is **Better Comments** (VS Code marketplace,
publisher: Aaron Bond). Install it before recording — without it, the tags
still read fine as plain text, they just won't be colour-highlighted.

## The tag legend

| Tag | Renders as | Use for | Maps to rubric line |
|---|---|---|---|
| `// ! ` or `# ! ` | 🔴 red | Security / data-safety critical lines | Data security (30 pts) |
| `// * ` or `# * ` | 🟢 green | The core mechanism being demonstrated | Performance optimization (20 pts) |
| `// ? ` or `# ? ` | 🔵 blue | Data interaction — filter/search/pagination logic | Data interaction (20 pts) |
| `// TODO ` or `# TODO ` | 🟠 orange | Still-open work, not yet demoable | n/a — cleanup marker |
| `// DEMO: ` or `# DEMO: ` | 🟣 highlighted (with `*` prefix) | The exact line to point at on camera | All — narration anchor |

**Format:** always `<tag> <ONE-LINE description in plain language>`. Keep it
short enough to read aloud in under 3 seconds — these are camera cues, not
documentation.

```python
# * DEMO: this only runs when the blob trigger fires — i.e. once per file change
def DietDataProcessor(myblob: func.InputStream):
```

```javascript
// ! DEMO: password never touches our code — sent straight to Person B's hashed/encrypted backend
fetch(AUTH_URL + '/api/login', { method: 'POST', body: JSON.stringify({email, password}) })
```

## Where to apply these — file by file

Claude Code: walk each file below and insert `DEMO:` tagged comments
immediately above the specific lines that prove each rubric point. Don't
comment every line — only the ones that are the actual evidence for a rubric
item, so there are ~1-3 tagged comments per concept, not a wall of comments.
Never change functional code, only add comment lines.

### `function_app.py` (your recipes API)
- Above the blob... *(there is no blob trigger in this file — it's Person A's — skip; this file's tags are data-interaction only)*
- `# ? DEMO:` above the `diet_type` filter line — proves diet-type filtering (5 pts)
- `# ? DEMO:` above the `keyword` / `str.contains` filter block — proves keyword search (10 pts)
- `# ? DEMO:` above the `page`/`page_size`/`total_pages` pagination math — proves pagination (5 pts)
- `# * DEMO:` above `_cached_df` check in `load_clean_data()` — proves you're reading Person A's already-cleaned data, not re-cleaning it yourself

### `webapp/index.html` (dashboard)
- `<!-- ! DEMO: -->` above the login-gate check that calls `GET /api/me` on load — proves the dashboard is actually gated (10 pts)
- `<!-- ! DEMO: -->` above the `#token=` hash-parsing block — proves GitHub OAuth token handoff works
- `<!-- ! DEMO: -->` above wherever the user's `name` gets rendered in the top-right — proves the display requirement
- `<!-- ! DEMO: -->` above the logout handler that clears the token — proves logout actually clears state, not just visually hides the dashboard
- `<!-- ? DEMO: -->` above the recipe search fetch call — proves the frontend is really hitting your live `/api/recipes` endpoint with real query params, not mock data

### `deploy-recipes-api.ps1`
- `# * DEMO:` above the `az functionapp create` call — useful if your video shows the deploy itself, not just the running result

### Person A's / Person B's files (if you're narrating over their code too)
Only add these if they've agreed to it — it's their file. If narrating their
code live from a shared screen without editing their repo, skip written tags
and just verbally point instead.

## One convention across all three parts
If Person A and Person B are open to it, ask them to use the same five tags
in their own files — makes the whole video visually consistent instead of
your section looking different from theirs. Not required, just nicer for a
single continuous recording.

## Final check before recording
- Every tagged `DEMO:` comment should map to something you can actually
  point the cursor at and say out loud in one breath
- No `DEMO:` tag left on dead code or something you removed
- Tags should read top-to-bottom in roughly the order you'll narrate them —
  performance first, then security, then data interaction, matching the
  presentation structure the rubric asks for

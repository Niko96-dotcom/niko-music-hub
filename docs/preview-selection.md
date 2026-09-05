# Automatic preview and card titles

Preview selection uses shared scanner rules, with no song/artist exceptions.

- Recognize delivery names such as `Artist - Song DEMO V2 (writers)` and `Artist - Song V2`, including exports with no production label. Retain artist/title case, numbers, hyphens and internal underscores. Remove the annotation suffix rather than deleting ordinary title words.
- A trustworthy named delivery supplies the card's base title ahead of a working folder name. A user-entered virtual title remains authoritative. Unstructured names retain the existing folder/CPR fallback.
- Penalize partial exports, reference files, mastering handoffs (`NO LIM`, `NO CLIP`, premaster), and very short clips. Internal Ableton processed samples are not full-song bounces merely because their names contain “Bounce”. Sample BPM labels and track-only artist fields are not song identities.
- Read WAV duration from RIFF chunks, including extra metadata and extended format chunks, rather than assuming a 44-byte header. Read other supported formats through native audio metadata. Unknown duration is neutral; CloudStorage files are not opened for duration during scanning.
- For named deliveries, `demo`, `prod`, `mix` and an absent label are not a universal chronology. Prefer a current delivery family, then its explicit revision, then modification time, format and duration. Version numbers are comparable within the same cleaned artist/title; an old alternate's V8 must not beat today's main demo V2. CPR save numbers do not override named delivery revisions.
- Root-level named exports get the same location evidence as Mixdown exports. Imported Audio files retain lower location confidence. A longer recording does not automatically beat a newer, plausible song-length revision.
- Cached automatic selections are reclassified and their base titles recalculated. Manual preview choices, ignored candidates and virtual titles remain intact. A fresh scan refreshes duration metadata.

These are filename/location/metadata heuristics, not an audio-content judgment. Candidate explanations and manual preview selection remain available for ambiguous sessions. Tests cover synthetic DAW files, artist/title parsing, alternate families, revision changes, technical exports, stems, short samples and cache behavior.

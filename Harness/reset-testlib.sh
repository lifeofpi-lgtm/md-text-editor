#!/bin/bash
# Recreates the sample library used by the screenshot scenarios.  usage: reset-testlib.sh <dir>
LIB="$1"
# Refuse anything that is not clearly a throwaway test library.
case "$LIB" in */TestLibrary) ;; *) echo "refusing: $LIB is not a TestLibrary path" >&2; exit 1 ;; esac
rm -rf "$LIB"; mkdir -p "$LIB/Clients/Acme" "$LIB/Personal" "$LIB/Drafts"
cat > "$LIB/Proposal.md" <<'MD'
# Acme Proposal

Here is the **first draft** of the proposal for [Acme](https://acme.test). It covers scope, pricing and _timeline_.

## Scope
- Discovery
- Build
- [ ] Review with client

> Keep the tone plain and direct.

```
code block here
```
MD
printf '# Weekly Review\n\nWhat went well this week and what to change.\n' > "$LIB/Weekly Review.md"
printf 'Just a loose note with no heading at all, written quickly.\n' > "$LIB/Loose note.txt"
printf '# Acme Kickoff\n\nNotes from the kickoff call.\n' > "$LIB/Clients/Acme/Kickoff.md"
printf '# Journal\n\nToday I wrote.\n' > "$LIB/Personal/Journal.md"
touch -t 202606011000 "$LIB/Loose note.txt"

# Releasing

Tuile is published to [RubyGems](https://rubygems.org/gems/tuile). The
release task comes from `bundler/gem_tasks`. We gate it on the project's
check suite: `rake release` runs `rake check` (specs, RuboCop, and RBS
regeneration) before it tags or pushes anything, so a release with
failing tests, lint offenses, or stale signatures aborts before it can
publish. See `Rakefile` — `task "release:guard_clean" => :check`.

## 1. Pre-flight checks

Although the release gate re-runs these, run them by hand first — a
failure caught here is a quick fix, whereas the same failure during
`rake release` aborts mid-release after the gem is already built.

From a clean working tree on `master`:

```sh
bundle install
bundle exec rake check      # specs + RuboCop + sig regeneration/validation
```

`rake check` runs `spec`, `rubocop`, and `sig` (the same three the
release gate runs). `rake sig` regenerates `sig/tuile.rbs` via `sord`
and validates it with `rbs`; **if it modifies the file, commit the
regenerated `sig/tuile.rbs` before releasing.** The release gate cannot
commit it for you — it only fails: a regenerated sig leaves the tree
dirty, and `release:guard_clean` then refuses to release.

If you ran the suite with `COVERAGE=true`, double-check `coverage/`
isn't committed.

## 2. Bump the version

Edit `lib/tuile/version.rb` and set `Tuile::VERSION` to the new value
following [SemVer](https://semver.org/).

Update `CHANGELOG.md`:

- **Reconcile it against the log first.** `git log --oneline vX.Y.Z..HEAD`
  and check every `feat:` / `fix:` commit has an entry — an entry is
  written when the change lands, so the ones that got skipped are exactly
  the ones nobody will notice missing. (The 0.11.0 release found the box
  layouts, a `StyledString#wrap` fix and a `ComboBox` fix all absent.)
- **Then reconcile it against the *signatures*, which is what catches what
  the log cannot.** A commit message reports what its author noticed; the
  public surface reports what actually changed. Diff it:

  ```sh
  git diff vX.Y.Z..HEAD -- sig/tuile.rbs | grep -E '^[-+].*(def |class |attr)'
  ```

  The removed (`-`) lines are the high-signal half — a deleted or re-scoped
  method is a breaking change whether or not anyone wrote `!` on the commit.
  The 0.14.0 release found two unlogged breaking changes this way (`extent`
  returning `Size` instead of `Rect`, and `Notification` / `ListDropdown`
  re-parenting to `Overlay`); 0.15.0 found a public `DateField#calendar_start`
  pair with no entry. Most `+` lines are private internals — check them
  against the file's `private` / `protected` markers before writing an entry.
- **Review every entry's length** against the one-sentence rule in
  AGENTS.md ("Documentation kinds"): lead with `Add` / `Fix` /
  `**Breaking:**`, ≈40 words, a second sentence only for a breaking
  change's migration, rationale deferred to `DECISIONS.md`. Entries are
  drafted mid-development, when the design argument is still warm and
  wants to spill into them; this is the checkpoint that catches it. Group
  the section `Add`, then `Fix`, then `**Breaking:**`.
- Move entries from `## [Unreleased]` into a new `## [x.y.z] - YYYY-MM-DD`
  section.
- Leave a fresh empty `## [Unreleased]` heading at the top.

Refresh `Gemfile.lock`. The gemspec reads `Tuile::VERSION`, so the lock
pins `tuile (x.y.z)`; bumping the version leaves it stale, and the next
`bundle install` (the release gate runs one) rewrites it — dirtying the
tree so `release:guard_clean` aborts mid-release. Run it now and confirm
the `tuile (x.y.z)` line updated:

```sh
bundle install
```

Commit all three files (no need to push — `rake release` pushes the
branch and tag for you in step 3):

```sh
git add lib/tuile/version.rb CHANGELOG.md Gemfile.lock
git commit -m "Release x.y.z"
```

## 3. Cut the release

```sh
bundle exec rake release
```

This task (from `bundler/gem_tasks`, with our guards) runs in order:

1. **build** — builds `tuile-x.y.z.gem` into `pkg/`.
2. **release:guard_version** — aborts unless `CHANGELOG.md` has a dated
   `## [x.y.z] - YYYY-MM-DD` section for the current `Tuile::VERSION`
   (catches a forgotten changelog entry or a placeholder date), and
   unless the `vx.y.z` tag does *not* yet exist (a present tag means the
   version was already released — bump `Tuile::VERSION` first). This runs
   before the spec suite so these cheap metadata mistakes fail fast.
3. **check** — runs `spec`, `rubocop`, and `sig`. Aborts the release on
   any test failure, lint offense, or — via the dirty tree left by a
   regenerated sig — signature drift.
4. **release:guard_clean** — refuses to proceed unless the working tree
   and index are clean (this is also what turns sig drift in step 3 into
   a hard stop).
5. **release:source_control_push** — creates the `vx.y.z` tag, then
   pushes the current branch followed by the tag to its remote.
6. **release:rubygem_push** — pushes the gem to RubyGems.

The tag check in step 2 is a local one (it reads `git tag`), so a
release cut from a different clone that this machine hasn't fetched
won't be seen here — RubyGems' own duplicate-version rejection is the
backstop in that case.

You'll need a RubyGems account with push rights on the `tuile` gem and
2FA configured (the gemspec sets `rubygems_mfa_required = true`, so
`gem push` will prompt for an OTP).

To rehearse the gate without touching anything, run `bundle exec rake
check` — it runs the same `spec`, `rubocop`, and `sig` the release gate
runs, but builds, tags, and pushes nothing.

## 4. Post-release

- Verify the new version appears at <https://rubygems.org/gems/tuile>.
- Verify the tag is on GitHub: <https://github.com/mvysny/tuile/tags>.

## If something goes wrong mid-release

The release sub-tasks run in the order listed in step 3. If the gem
push (step 6) fails after the tag was pushed (step 5), fix the
underlying issue and run `gem push pkg/tuile-x.y.z.gem` directly — **do
not** re-run `rake release`: the tag now exists, so `guard_version`
would abort. If the tag itself is wrong, delete it locally *and* on the
remote (`git push --delete origin vx.y.z`) before retrying; note that
`source_control_push` pushes the branch *before* the tag, so a tag-push
failure can leave the branch already pushed.

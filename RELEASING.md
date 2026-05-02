# Releasing

Tuile is published to [RubyGems](https://rubygems.org/gems/tuile). The
release task comes from `bundler/gem_tasks` and **does not run tests or
validate signatures** — it only builds, tags, and pushes. Run the
checks below by hand first.

## 1. Pre-flight checks

From a clean working tree on `master`:

```sh
bundle install
bundle exec rake spec       # full unit + examples suite
bundle exec rake rubocop    # lint
bundle exec rake sig        # regenerate sig/tuile.rbs and validate it
```

`rake sig` runs `sord` and then `rbs validate`; if it modifies
`sig/tuile.rbs`, commit the regenerated file before releasing. CI also
gates on RBS drift, so a release with stale sigs will fail there.

If you ran the suite with `COVERAGE=true`, double-check `coverage/`
isn't committed.

## 2. Bump the version

Edit `lib/tuile/version.rb` and set `Tuile::VERSION` to the new value
following [SemVer](https://semver.org/).

Update `CHANGELOG.md`:

- Move entries from `## [Unreleased]` into a new `## [x.y.z] - YYYY-MM-DD`
  section.
- Leave a fresh empty `## [Unreleased]` heading at the top.

Commit:

```sh
git add lib/tuile/version.rb CHANGELOG.md
git commit -m "Release x.y.z"
git push
```

## 3. Cut the release

```sh
bundle exec rake release
```

This task (from `bundler/gem_tasks`):

1. Builds `tuile-x.y.z.gem` into `pkg/`.
2. Creates and pushes the `vx.y.z` git tag.
3. Pushes the gem to RubyGems.

You'll need a RubyGems account with push rights on the `tuile` gem and
2FA configured (the gemspec sets `rubygems_mfa_required = true`, so
`gem push` will prompt for an OTP).

## 4. Post-release

- Verify the new version appears at <https://rubygems.org/gems/tuile>.
- Verify the tag is on GitHub: <https://github.com/mvysny/tuile/tags>.
- Optionally draft a GitHub Release pointing at the tag and pasting the
  changelog entry.

## If something goes wrong mid-release

`rake release` runs steps 1–3 above as separate sub-tasks. If the gem
push fails after the tag was pushed, fix the underlying issue and run
`gem push pkg/tuile-x.y.z.gem` directly — don't re-tag. If the tag
itself is wrong, delete it locally *and* on the remote
(`git push --delete origin vx.y.z`) before retrying.

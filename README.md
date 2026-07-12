# nupm-registry

Private [nupm](https://github.com/nushell/nupm) registry for ramda's personal Nushell packages,
hosted at `https://raw.githubusercontent.com/zaynram/nupm-registry/main/registry.nuon`.

- `registry.nuon` — the registry index (`[name, path, hash]`); each hash is `md5-` of the
  package declaration's canonical `to nuon` serialization (what nupm re-serializes to verify).
- `<name>.nuon` — one declaration per package: a `[name, version, path, type, info]` table with
  one row per version. All rows are `git`-type so the registry works from any machine: `session`
  and `watch` point back at this repository (`path` = `pkgs/<name>`), `tasks` points at
  [zaynram/nushell-tasks](https://github.com/zaynram/nushell-tasks).
- `pkgs/` — package sources hosted in this repository.
- `pack.nu` — refreshes `registry.nuon` hashes from the declarations; run it after any
  declaration change and commit the result.

Registered as `ramda` in `$env.NUPM_REGISTRIES` via the persisted index
(`nupm registry add ramda <raw registry.nuon url> --save`). Install with
`nupm install <name> --registry ramda`.

nupm caches registry indexes and git clones without expiry — after pushing an update here or
to a package repository, run `nupm registry refresh ramda` so the next install re-fetches.

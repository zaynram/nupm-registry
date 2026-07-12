# nupm-registry

Private [nupm](https://github.com/nushell/nupm) registry for ramda's personal Nushell packages.

- `registry.nuon` — the registry index (`[name, path, hash]`); hashes are `md5-` of each
  package file's canonical `to nuon` serialization.
- `<name>.nuon` — one file per package (`[name, version, path, type, info]`), one row per version.
- `pkgs/` — `local`-type package sources hosted in this repository (`session`, `watch`).
  `tasks` lives in `../ramda-doc/scripts/tasks` and is referenced relatively, so this repo
  and `ramda-doc` must stay siblings under `~/code/`.

Registered as `ramda` in `$env.NUPM_REGISTRIES` via the persisted index
(`nupm registry add ramda ~/code/nupm-registry/registry.nuon --save`). Install with
`nupm install <name> --registry ramda`.

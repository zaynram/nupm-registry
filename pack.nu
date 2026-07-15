#!/usr/bin/env -S nu --stdin

const ROOT: path = path self . | path expand
const NUON: path = path self registry.nuon | path expand

# Update the package registry with the local packages.
#
# nupm verifies a package declaration by re-serializing it (`open <name>.nuon
# | to nuon`) and comparing an `md5-`-prefixed digest of that canonical form,
# so rows must carry exactly that hash — never a digest of the raw file bytes
# or of the package's own nupm.nuon manifest.
#
# Consumers cache the registry index and git clones and never expire them:
# after pushing a registry or package update, run `nupm registry refresh ramda`
# before installing again.
def main [
  --confirm (-c) = true # Await confirmation before writing to disk
  --remote (-r) # Fetch and update the manifest files from their remotes (if applicable)
  --force (-f) # Update the NUON files regardless if there are no changes
]: nothing -> table<name: string, path: path, hash: string> {
  cd $ROOT
  let mods: list<path> = glob *.nuon --exclude [**/registry.nuon] --no-symlink --no-dir
  if $remote {
    for f in $mods {
      let row: record = open $f
      if $row.type != git { continue }
      let url: oneof<string, nothing> = $row.info?.url? | default $row.info?.git?
      if $url == null { continue }
      let new: record = $url | url parse
        | update host raw.githubusercontent.com
        | update path {
          append ($row.info.revision? | default $row.info.ref?)
          | compact
          | path join nupm.nuon
        }
        | url join
        | http get $in
        | select --optional description version
        | if not $force and $in == ($row | select --optional description version) { continue } else { }
        | compact --empty
      $row | merge $new | if $confirm {
        let item = $in
        $item | table --expand | print
        print "Save remote changes? ([y]/n):"
        input listen --types=[key]
        | if $in has code and $in.code == n { continue } else { $item }
      } else { }
      | to nuon --indent=4 --pretty --raw-strings
      | save --force $f
    }
  }
  let prev: table = append (open $NUON) | sort-by name
  let curr = $mods
    | par-each {|it|
      let name = $it | path parse | get stem
      let hash: string = $"md5-($it | open | to nuon | hash md5)"
      let path = $it | path relative-to $ROOT
      {name: $name hash: $hash path: $path}
    }
    | where {|x|
      if $force { return true }
      let row: oneof<nothing, record> = $prev | where name == $x.name | first
      $row == null or $row.hash != $x.hash
    }
    | collect
    | if $confirm and ($in | is-not-empty) {
      input list "Select changes" --multi
    } else { }
    | if ($in | is-empty) { return $prev } else { }
    | compact --empty
    | sort-by name
  let next = $curr | append $prev | uniq-by name
  $next | to nuon --pretty --indent=2
  | if (which nu-lint | is-not-empty) { nu-lint --stdin --fix } else { }
  | save --force $NUON
  return $next
}

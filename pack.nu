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
]: nothing -> table<name: string, path: path, hash: string> {
  cd $ROOT
  let prev: table = append (open $NUON) | sort-by name
  let curr = glob *.nuon --exclude [**/registry.nuon]
    | par-each {|it|
      let name = $it | path parse | get stem
      let hash: string = $"md5-($it | open | to nuon | hash md5)"
      let path = $it | path relative-to $ROOT
      {name: $name hash: $hash path: $path}
    }
    | collect
    | if $confirm {
      input list "Select changes" --multi
      | if ($in | is-empty) { return $prev } else { }
    } else { }
    | compact --empty
    | sort-by name
  let next = $curr | append $prev | uniq-by name
  $next | to nuon --pretty --indent=2
  | if (which nu-lint | is-not-empty) { nu-lint --stdin --fix } else { }
  | save --force $NUON
  return $next
}

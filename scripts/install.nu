#!/usr/bin/env -S nu --stdin
use std/log

# The URL parts for this file's hosted `registry.nuon`.
const REGISTRY: record<scheme: string, host: string, path: string> = {
  scheme: https
  host: raw.githubusercontent.com
  path: /zaynram/nupm-registry/main/registry.nuon
}
# The modules to install when this script is run with `--default`.
const DEFAULTS: list<string> = [issue tasks]

# Add the repository's `registry.nuon` package globally with `nupm`.
#
# Runs iff nupm manages this machine ($env.NUPM_HOME is set to an existing directory).
# Otherwise, it will throw an error immediately and prevent installation.
def --env main [
  ...modules: string@_modules # The names of any modules to install automatically
  --name (-n): string = ramda # The key to add the registry under
  --default (-d) # Install the default set of modules (tasks, issue)
]: nothing -> nothing {
  if not ($env has NUPM_HOME) or ($env.NUPM_HOME | path type) != dir {
    let msg: string = 'setup.nupm-tasks skipped; $env.NUPM_HOME is not a directory'
    log critical $msg
    error make --unspanned $msg
  }
  let url: string = $REGISTRY | url join
  let include: path = $env.NUPM_HOME | path join modules
  # --no-confirm: any nupm prompt would hang invisibly in the captured child.
  let commands: string = match {modules: $modules default: $default} {
    {modules: null default: false} => []
    {modules: $m default: false} => $m
    {modules: $m default: true} => { $DEFAULTS | append $m | uniq }
  } | par-each {|mod| $"nupm install --force --no-confirm --registry='($name)' '($mod)'" }
    | prepend ['use nupm' $"nupm registry add --save '($name)' '($url)'"]
    | str join '; '

  let msg: string = $"running commands:\n>>> ($commands | nu-highlight)"
  log info $msg

  ^$nu.current-exe ...[
    --no-config-file
    --include-path=($include)
    --commands=($commands)
  ] out+err>|
  | complete
  | if $in.exit_code != 0 {
    let msg: string = $"`nupm registry add`/`nupm install` did not succeed:\n($in.stdout?)"
    log error $msg
    error make --unspanned $msg
  }
  if $env not-has NUPM_REGISTRIES { $env.NUPM_REGISTRIES = {} }
  $env.NUPM_REGISTRIES | upsert $name $url | wrap NUPM_REGISTRIES | load-env
  log info $"(ansi g)added registry '($name)'(ansi rst)"
}

def _modules []: nothing -> list<string> {
  let url: string = $REGISTRY | url join
  http get $url | get name
}

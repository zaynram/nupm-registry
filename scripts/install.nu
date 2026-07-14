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
def main [
  --name (-n): string = ramda # The key to add the registry under
  --install (-i): list<string>@_modules # The names of any modules to install automatically
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
  let commands: string = match {install: $install default: $default} {
    {install: null default: false} => []
    {install: $i default: false} => $i
    {install: $i default: true} => { $DEFAULTS | append $i | uniq }
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
  log info $"(ansi g)setup.nupm-tasks done(ansi rst)"
}

def _modules []: nothing -> list<string> {
  let url: string = $REGISTRY | url join
  http get $url | get name
}

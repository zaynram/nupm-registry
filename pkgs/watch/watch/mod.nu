# nu-lint-ignore-file: max_function_body_length, block_brace_spacing, unhandled_external_error, error_make_for_non_fatal
const PROMPT: string = $"\n(ansi violet)>>>(ansi rst)"
const ESC: record = {
  home: (ansi home)
  el: (ansi erase_line)
  cnorm: (ansi cursor_on)
  civis: (ansi cursor_off)
  smcup: (ansi --escape ?1049h)
  rmcup: (ansi --escape ?1049l)
  wrap: (ansi --escape ?7h)
  nowrap: (ansi --escape ?7l)
}

# Built-in keybinds; merged with user-supplied keybinds in `monitor`.
# `visible: false` means the keybind is suppressed from the footer hint row.
const BUILTIN_KEYS: list = [
  {
    code: q
    modifiers: []
    text: 'q to quit'
    visible: true
    break: true
  }
  {
    code: c
    modifiers: ['keymodifiers(control)']
    text: 'ctrl+c to quit'
    visible: false
    break: true
  }
  {
    code: o
    modifiers: []
    text: 'o to toggle overlay'
    visible: true
    break: false
    toggle: {ui: true}
  }
]

def "ansi csr" [bottom: int]: nothing -> string { ansi --escape $"1;($bottom)r" }
def "ansi cup" [row: int col: int = 0]: nothing -> string { ansi --escape $"($row + 1);($col + 1)H" }
def "term height" []: nothing -> int { (term size).rows }
def "term width" []: nothing -> int { (term size).columns }
# Serialize a closure to a header-friendly string. Brittle (depends on
# serializer formatting), but isolated here so it can be swapped later.
def "closure repr" []: closure -> string {
  let c: closure = $in
  try {
    $c
    | to nuon --serialize --raw-strings
    | parse "{_} {value} }{_}"
    | get 0.value
  } catch {
    $c | to text
  }
}

const DOT: string = $"(ansi dark_gray) ·(ansi rst)"

# Truncate-and-join a list of footer hint strings to fit `width`.
def "fit hints" []: list<string> -> string {
  let set: list<string> = $in
  let columns: int = term width
  if ($set | is-empty) { return "" }
  let str: string = $set | str join $DOT
  let sum: int = $str | ansi strip | str length
  if ($set | length | $in - 1 + $sum) <= $columns { return $str }
  let index: int = $str | str index-of --end $DOT
  let text: string = $str | str substring 0..($index - 1) | str trim --right
  $"($text)(ansi dark_gray)…(ansi rst)"
}

# Render the user closure's output, padded/truncated to fit the render region.
def "render body" [render: int suppress: bool]: closure -> list<string> {
  let c: closure = $in
  let o: any = if not $suppress { do --env $c } else {
    try { do $c } catch {|err| $"(ansi r)($err.msg)(ansi rst)" }
  }
  if ($o | is-empty) { return ['' ''] }
  let full: list<string> = match ($o | describe) {
    list<string> => $o
    string => { $o | lines }
    $x if $x =~ list => { $o | into string }
    $x if $x =~ table => { $o | lines }
    $x if $x =~ record => { $o | table --expand --theme none | lines }
    _ => { $o | to nuon --serialize --indent 4 | lines }
  }
  let n: int = $full | length | append ($render | append 1 | math max) | math min
  let body: list<string> = $full | first $n
  let count: int = $render - ($body | length)
  if $count <= 0 { $body } else {
    1..$count | each { '' } | prepend $body
  }
}

# Compose the footer hint rows (built-in keys + custom keys).
def "footer lines" [
  ...custom: record
]: list<record> -> string {
  let builtin: list = $in
  let n: int = $builtin | append $custom | where ($it | is-not-empty) | length
  let rows: int = term height
  let prefix = $'(ansi cup ($rows - $n))($ESC.el)'
  let base = $builtin | each { $' (ansi light_gray)($in.text)(ansi rst)' } | fit hints
  if ($custom | is-empty) { $'($prefix)($base)' } else {
    let text = $custom | each { $' (ansi blue)($in.text | str trim --left)(ansi rst)' } | fit hints
    $'($prefix)($base)(ansi cup ($rows - 1))($ESC.el)($text)'
  }
}

def teardown []: nothing -> nothing {
  print --no-newline $"(ansi csr (term height | $in - 1))($ESC.cnorm)($ESC.wrap)($ESC.rmcup)"
  stty sane | ignore
}

def --env state [
  name: string
  --toggle
  --set: oneof<nothing, bool> = null
]: [
  nothing -> oneof<nothing, bool>
] {
  if $env not-has __watch_state { load-env {__watch_state: {}} }
  let current: record = $env.__watch_state | default false $name
  if $set != null {
    $env.__watch_state = $current | update $name $set
  } else {
    let val: bool = $current | get --optional $name
    if not $toggle { return $val }
    $env.__watch_state = $current | update $name (not $val)
  }
}

# Run an auto-updating command in a target directory.
#
# To control loop behavior from keybinding closures you
# can return `true` to break (must be explicit literal, not just truthy).
# For cases where more than one keybind matches the provided input, if any
# value is exactly `true`, the loop will be broken after all remaining
# matching closures are executed.
#
# The minimum supported `--wait` interval is `200ms`.
@category process
export def monitor [
  --cwd (-d): path # Run the closure from this directory instead of the caller's
  --repr (-r): string # Override the command serialization header value
  --suppress (-s) # Suppress errors; prints them to stderr but loop continues
  --keybinds (-k): table<code: string, modifiers: list<string>, handler: closure, text: string> # Extra key handlers merged with the built-ins; `text` is the footer hint
  --ui = true # Whether the header is shown by default (can be toggled back on)
  --pad: int = 1 # Amount of lines to pad between header and content
  --wait (-w): duration = 2sec # The refresh interval as a duration; used as `input listen` timeout duration
]: closure -> nothing {
  if $cwd != null { $cwd | path expand | cd $in }

  let c: closure = $in
  let t: duration = $wait | append 200ms | math max

  let repr: string = $repr | default { $c | closure repr } | str trim
  let custom: list = $keybinds | default []
  let all: list = $BUILTIN_KEYS | append $custom
  let bottom: int = if ($custom | is-empty) { 1 } else { 2 }

  try {
    print --no-newline $"($ESC.smcup)($ESC.nowrap)"
    state show --set $ui
    loop {
      let view: record<rows: int, columns: int> = term size
      let show: bool = state show
      let head: list<string> = if not $show { [] } else {
        let base: list<string> = $"(ansi attr_bold)(date now)(ansi rst) ($PROMPT) ($repr | nu-highlight)" | lines
        if $pad <= 0 { $base } else { 1..$pad | par-each { '' } | prepend $base }
      }
      let foot: string = if not $show { [] } else {
        $BUILTIN_KEYS | where $it.visible
      } | footer lines ...$custom
      let n: int = if $show { $view.rows - $bottom } else { $view.rows } | $in - 1
      let body: string = $c
        | render body ($head | length | $n - $in) $suppress
        | prepend $head
        | each { $"($in)($ESC.el)" }
        | str join "\n"
        | $'($in)($foot)'

      print --no-newline $'(ansi csr $n)($ESC.civis)($ESC.home)($body)'

      let event: oneof<record, nothing> = try { input listen --timeout $t --types [key] }
      if $event == null or $event.code? == null { continue }

      let binds: list = $all | where code == $event.code and modifiers == $event.modifiers
      # Built-in: toggle overlay (mutates $show).
      if ($binds.toggle?.ui? | any {}) { state show --toggle }
      # Built-in: explicit break flag.
      if ($binds.break? | any {}) { break }

      let extra: list<closure> = $binds | get --optional handler | compact
      # Skip to next iteration if no matching custom handlers.
      if ($extra | is-empty) { continue }
      # Run custom handlers in normal terminal mode then restore.
      print --no-newline $"(ansi csr (term height | $in - 1))($ESC.cnorm)($ESC.wrap)(ansi --escape 2J)"
      let done: bool = $extra | each { do --capture-errors --env $in.handler } | any {}
      print --no-newline $"($ESC.nowrap)($ESC.civis)"
      # Defer exiting loop to AFTER terminal state restored.
      if $done { break }
    }
  } catch {|err|
    teardown
    error make --unspanned {
      msg: "monitor exited with errors"
      inner: [$err]
      label: {text: closure span: (metadata $c).span}
    }
  }
  teardown
}

def "input dismiss" [prompt?: string]: nothing -> nothing {
  print ($prompt | default "press any key to dismiss")
  input listen --types [key] | ignore
}
def "input select" [prompt: string column: string --case-sensitive (-c)]: table -> list<string> {
  input list $"(ansi dark_gray)($prompt)(ansi rst)" --multi --fuzzy --case-sensitive $case_sensitive
  | get --optional $column
  | flatten
  | compact --empty
}
def "input pick" [
  prompt: string
  --style (-s): string
  --display (-d): string
  --no-abort (-n)
  --fill: any
  --default: oneof<string, record>
]: oneof<list<string>, table> -> oneof<any, list<any>> {
  let data: oneof<list<string>, table> = $in
  let text: bool = $data | describe | $in !~ table
  let keys: list<string> = if not $text { ($data | columns) } else { [] }
  let main: string = if not $text { ($display | default { $keys | first }) }
  $data
  | default $fill ...$keys
  | par-each --keep-order {|opt|
    let original: string = if $text { $opt } else { $opt | get --optional $main }
    let styled: string = $"($style | default { ansi cyan })($original)(ansi rst)"
    if $text { $styled } else { $opt | update $main $styled }
  }
  | if not $no_abort {
    let abort: string = $"(ansi red)cancel(ansi rst)"
    $in | append (
      if $text { $abort } else {
        {
          ($main): $abort
        }
      }
    )
  }
  | collect { input list $"(ansi dark_gray)($prompt)(ansi rst)" }
  | ansi strip ...$keys
  | default $default
}

const GSKEEP: list<string> = [
  ignored
  conflicts
  ahead
  behind
  stashes
  repo_name
  branch
  remote
  state
]

def --wrapped "git list" [...rest: string]: nothing -> table {
  await { git ls-files --exclude-standard ...($rest) }
  | lines
  | par-each {|p| try { ls $p } catch { {name: $p type: - size: - modified: -} } }
  | flatten
  | compact --empty
}
def "ignore list" []: nothing -> list<glob> {
  pwd
  | path join .gitignore
  | open
  | lines
  | where not ($it | str starts-with '#') and ($it | str trim | is-not-empty)
  | into glob
}

def "query status" [predicate: closure negate: bool = false]: nothing -> bool {
  gstat
  | into record
  | do --ignore-errors $predicate
  | into bool
  | if $negate { not $in } else { $in }
}
def "is clean" [--not]: nothing -> bool {
  await --status { git diff-index --quiet HEAD -- }
  | if $not { not $in } else { $in }
}

def "has ahead" [--not]: nothing -> bool {
  query status {
    get ahead | $in > 0
  } $not
}
def "has behind" [--not]: nothing -> bool {
  query status {
    get behind | $in > 0
  } $not
}

def "with action" [name: string body: closure]: nothing -> oneof<nothing, bool> {
  print $"[action=(ansi blue_italic)($name)(ansi rst)]"
  try { do --capture-errors $body } catch {|| print --stderr $in.rendered? }
  | match $in {
    1 => {
      return false # Skip dismissal; keep monitoring
    }
    2 => {
      return true # Skip dismissal; stop monitoring
    }
    _ => {
      input dismiss # Run dismissal; keep monitoring
    }
  }
}

def "gate action" [
  resolve: closure
  --signals (-s): record<ok: int, err: int> = {}
]: [
  table<condition: closure, reason: string> -> oneof<nothing, int>
  table<condition: closure, reason: string, style: string> -> oneof<nothing, int>
] {
  let rejections: list<string> = $in
    | where (do --ignore-errors $it.condition)
    | par-each --keep-order { $"($in.style? | default { ansi red })($in.reason)(ansi rst)" }
  if ($rejections | is-not-empty) {
    for msg in $rejections { print --stderr $msg }
    return $signals.err?
  }
  do --capture-errors $resolve | default $signals.ok?
}

def "read action" [left: string --right (-r): string --start (-s): string]: nothing -> string {
  use std/util repeat
  let rprompt: string = $right | default "alt+ret to insert newline"
  let padding: string = ' ' | repeat (
      term width
      | $in - ($rprompt | str length | $in + 2)
      | append 0
      | math max
    ) | str join
  let prompt: string = [
    $" (ansi attr_underline)($left)(ansi rst): ($padding)(ansi dark_gray)($rprompt)(ansi rst)"
    $" (ansi attr_dimmed)($start | default > | str trim --right) "
  ] | str join $"($ESC.el)\n"
  input --reedline $prompt
}

# Spawn a git status watcher for the target repository.
@category source-control
export def --wrapped "git watch" [
  ...rest: string # Arguments for the git status invocation; overrides defaults
  --cwd (-c): path # Path to the repository to spawn the process in
  --no-tag (-n) # Omit the `tag` value from the `gstat` record
  --interval (-i): duration # Duration to wait between each iteration
]: nothing -> nothing {
  let args: list<string> = if ($rest | is-not-empty) { $rest } else { [-s -unormal --renames] }
  let repr: string = $'git status ($args | str join " ")'
  let keep: list<string> = $GSKEEP | append (if not $no_tag { [tag] }) | compact

  {
    gstat
    | select ...$keep
    | items {|k v| if ($v | into bool --relaxed) { {$k: $v} } }
    | compact
    | into record
    | merge {files: (await { git status ...$args } | nu-highlight)}
    | compact --empty
    | table --width (term width) --theme frameless
  } | (
    monitor
    --wait $interval
    --cwd ($cwd | default (pwd))
    --repr $repr
    --keybinds [
      {
        code: c
        modifiers: []
        text: 'c to commit'
        handler: {
          with action commit {
            [
              [condition reason];
              [{ is clean } "there are no changes to commit"]
            ]
            | gate action {||
              let action: closure = {|...rest: string| git commit ...$rest }
              let options = [[group mode]; [staged all] [tracked all] [tracked select] [modified all] [modified select]]
              let choice: record = $options
                | input pick "select changes to commit" --default {group: none}
              let extra: list<string> = match $choice {
                null => { return 1 }
                {mode: null} => { return 1 }
                {group: $g} if $g not-in [staged tracked modified] => { return 1 }
                {group: $g mode: select} => {
                  git list --modified ...(if $g != tracked { [--others] } else { [] })
                  | input select "select files to commit" name
                }
                {group: modified mode: all} => { await --print { git add --all } }
                {group: tracked mode: all} => [--all]
                {group: staged mode: all} => []
              } | append [
                  --message
                  (read action "commit message")
                ] | compact --empty
              await --print $action ...$extra
              return 0
            }
          }
        }
      }
      {
        code: p
        modifiers: []
        text: 'p to push'
        handler: {
          with action push {
            [
              [condition reason style];
              [{ has ahead --not } "there are no new commits to push" (ansi yellow)]
              [{ has behind } "remote changes must be pulled first" (ansi yellow)]
            ]
            | gate action {
              let options: list<string> = [confirm]
              let choice: string = $options | input pick "push changes to remote"
              if $choice != confirm { return 1 }
              await --print { git push }
              return 0
            }
          }
        }
      }
      {
        code: f
        modifiers: []
        text: 'f to fetch'
        handler: {
          with action fetch { await --print { git fetch } }
        }
      }
      {
        code: l
        modifiers: []
        text: 'l to pull'
        handler: {
          with action pull {
            [
              [condition reason style];
              [{ has behind --not } "working tree is up-to-date with remote" (ansi cyan)]
              [{ is clean --not } "working tree has uncommitted changes" (ansi yellow)]
            ]
            | gate action { await --print { git pull } }
          }
        }
      }
      {
        code: i
        modifiers: []
        text: 'i to ignore'
        handler: {
          with action ignore {
            let ignored: list<glob> = ignore list
            let gitignore: path = pwd | path join .gitignore
            let choice: string = [search remove append] | input pick "select action"
            match $choice {
              cancel => { return 1 }
              search => {
                let entries: table = $ignored
                  | par-each { try { ls $in } }
                  | flatten
                  | compact --empty
                let prompt: string = $"(ansi dark_gray)ignored files \(ret or esc to close)(ansi rst)"
                $entries | input list --fuzzy $prompt
              }
              remove => {
                let removals: list<glob> = $ignored
                  | each { nu-highlight }
                  | input list $"(ansi dark_gray)select entries to remove(ansi rst)" --multi --fuzzy
                  | ansi strip
                  | into glob
                if ($removals | is-not-empty) {
                  $ignored | where $it not-in $removals | save --force $gitignore
                } else {
                  print --stderr $"(ansi yellow)no entries to remove(ansi rst)"
                }
              }
              append => {
                let files: list<path> = git list
                  | input select $"(ansi dark_gray)select files to ignore(ansi rst)" name
                if ($files | is-not-empty) {
                  $files | save --append $gitignore
                } else {
                  print --stderr $"(ansi yellow)no files to ignore(ansi rst)"
                }
              }
            }
            return 0
          }
        }
      }
      {
        code: b
        modifiers: []
        text: 'b to change branch'
        handler: {
          with action branch {
            [
              [condition reason style];
              [{ is clean --not } "working tree has uncommitted changes" (ansi yellow)]
            ]
            | gate action {
              let action: closure = {|name: string| git checkout $name }
              let choice: string = await { git branch --color --list }
                | lines
                | input pick "select branch"
                | parse "{_} {branch}"
                | get --optional branch.0
              if $choice == null { return 1 }
              await --print $action ($choice | str trim)
              return 0
            }
          }
        }
      }
    ]
  )
}

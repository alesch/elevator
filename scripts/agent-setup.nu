#!/usr/bin/env nu

def main [agent_name: string] {
    let agents_root = "agents"
    let base_port = 4001

    let cyan = (ansi cyan_bold)    # Or (ansi cb)
    let green = (ansi green_bold)  # Or (ansi gb)
    let bold = (ansi b)        # Or (ansi b)
    let dim = (ansi d)      # Note: 'dimmed', not 'dim' or 'faint'
    let reset = (ansi reset)

    let agent_dir = $"($agents_root)/($agent_name)"
    let branch = $"agent/($agent_name)"

    print $"\n($cyan)--- 🤖 Setting up Sandbox for Agent: ($agent_name) ---($reset)"

    # 1. Create Branch & Worktree
    print "📦 Preparing Git Worktree..."
    if not ($agents_root | path exists) {
        mkdir $agents_root
    }

    if ($".gitignore" | path exists) {
        let content = open .gitignore
        if ($content | str contains $"($agents_root)/") == false {
            $"\n# Multi-Agent Sandboxes\n($agents_root)/" | save --append .gitignore
        }
    }

    let branch_exists = (do { ^git rev-parse --verify $branch } | complete).exit_code == 0
    if not $branch_exists {
        ^git branch $branch main
    }

    if ($agent_dir | path exists) {
        print $"⚠️  Directory ($agent_dir) already exists."
    } else {
        let worktree_result = (do { ^git worktree add $agent_dir $branch } | complete)
        if $worktree_result.exit_code != 0 {
            let error_detail = if ($worktree_result.stderr | is-empty) { $worktree_result.stdout } else { $worktree_result.stderr }
            error make { msg: $"Git Worktree Error: ($error_detail | str trim)" }
        }
    }

    # 2. Assign Unique Port
    print "🔢 Assigning Parallel Port..."
    let existing_ports = (
        glob $"($agents_root)/*/.env"
        | each { |env_file|
            let val = (open $env_file | lines | find "PORT=" | parse "export PORT={port}" | get -o port.0)
            if ($val | is-not-empty) { $val | into int } else { null }
        }
        | compact
    )

    let port = if ($existing_ports | is-empty) { $base_port } else { ($existing_ports | sort | last) + 1 }
    $"export PORT=($port)\nexport PHX_HOST=localhost\n" | save -f $"($agent_dir)/.env"

    # 3. Mise trust
    if (which mise | is-not-empty) {
        ^mise trust $agent_dir
    }

    # 4. Symlink Heavy Dependencies
    print "🔗 Symlinking Dependencies..."
    let root_dir = $env.PWD
    let targets = ["node_modules" "priv/plts" "deps"]

    for target in $targets {
        let source = ($root_dir | path join $target)
        let destination = ($agent_dir | path join $target)

        if ($source | path exists) {
            if ($destination | path exists) { rm -rf $destination }
            ^ln -s $source $destination
        }
    }

    print $"\n($green)✅ Sandbox Ready at: ($agent_dir)($reset)"
    let cmd_text = $"env PORT=($port) iex -S mix phx.server"
    print $"($dim)\(To start the server, run: ($cmd_text) in that directory\)($reset)\n"
}

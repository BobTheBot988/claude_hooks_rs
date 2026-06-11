
alias b := build
alias i := install
alias u := uninstall

root_dir := justfile_dir()
bin_dir := home_dir() / ".local" / "bin"

# Auto-discover hook binary names from member Cargo.toml [[bin]] sections
[private]
_hooks := `grep -rl '\[\[bin\]\]' --include='Cargo.toml' "{{root_dir}}" | xargs grep 'name =' | sed 's/.*"\(.*\)"/\1/'`

# Build all hook binaries
build:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v lld >/dev/null 2>&1; then
        echo "lld found! Compiling with LLVM LLD Linker..."
        export RUSTFLAGS="-C link-arg=-fuse-ld=lld"
    else
        echo "lld NOT found! Falling back to default system linker (ld)..."
        export RUSTFLAGS=""
    fi

    echo "Building hooks..."
    cargo build --release --manifest-path "{{ root_dir }}/Cargo.toml"

    echo -e "\n--- VERIFYING DEPENDENCIES VIA READELF ---"
    for hook in {{ _hooks }}; do
        printf '\n[%s shared libraries]:\n' "$hook"
        readelf -d "{{ root_dir }}/target/release/$hook" \
            | grep -E 'NEEDED|Shared library' \
            || echo "  (Statically linked / No dependencies)"
    done

# Install hook binaries with md5sum skip
install: build
    #!/usr/bin/env bash
    set -euo pipefail
    echo -e "\nBEGINNING INSTALL..."
    mkdir -p "{{ bin_dir }}"

    count=1
    total=$(echo '{{ _hooks }}' | wc -w)
    for hook in {{ _hooks }}; do
        src="{{ root_dir }}/target/release/$hook"
        dest="{{ bin_dir }}/$hook"

        if [ -f "$dest" ] && [ "$(md5sum < "$src")" = "$(md5sum < "$dest")" ]; then
            echo "[$count/$total] $hook up-to-date. Skipping."
        else
            cp "$src" "$dest"
            echo "=> [$count/$total] Installed $hook"
        fi
        count=$((count + 1))
    done
    echo "INSTALL COMPLETE!"

# Uninstall hooks. Omit name to remove all, or specify one: just u pre_hook
uninstall name="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{ name }}" ]; then
        target="{{ bin_dir }}/{{ name }}"
        if [ -f "$target" ]; then
            rm "$target"
            echo "Removed {{ name }}"
        else
            echo "{{ name }} not installed at $target"
        fi
    else
        for hook in {{ _hooks }}; do
            target="{{ bin_dir }}/$hook"
            if [ -f "$target" ]; then
                rm "$target"
                echo "Removed $hook"
            else
                echo "$hook not installed"
            fi
        done
        echo "UNINSTALL COMPLETE!"
    fi

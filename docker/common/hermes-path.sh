# shellcheck shell=sh
# Debian's /etc/profile replaces the Docker image PATH for login shells.
# Restore the Hermes paths so `bash -lc 'hermes ...'` behaves like the
# supervised services and ordinary container commands.
for hermes_path in \
    /opt/data/.local/bin \
    /opt/hermes/.venv/bin \
    /opt/hermes/bin
do
    case ":${PATH:-}:" in
        *":${hermes_path}:"*) ;;
        *) PATH="${hermes_path}${PATH:+:${PATH}}" ;;
    esac
done
export PATH
unset hermes_path

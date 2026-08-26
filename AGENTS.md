# Repository agent instructions

- Run `gh` commands that read or use GitHub credentials outside the sandbox.
  A sandboxed `gh auth status` can report the keyring token as invalid even when
  the host credential is healthy; never diagnose GitHub authentication from
  that sandboxed result.

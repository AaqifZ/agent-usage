#!/usr/bin/env bash
# Sourced by install.sh and package-app.sh. Sets SIGN_IDENTITY.
#
# Keychain "Always Allow" is bound to a binary's designated requirement.
# An ad-hoc signature pins that requirement to the exact cdhash, so every
# rebuild loses the approval and macOS prompts for the login password again.
# A certificate signature pins it to the certificate instead, so one
# approval survives every rebuild. The certificate need not be trusted.
#
# Override with AGENT_USAGE_SIGN_IDENTITY="<certificate name or SHA-1>".

SIGN_IDENTITY="${AGENT_USAGE_SIGN_IDENTITY:-Aaqif Local Signing}"

if ! security find-identity -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
  echo "WARNING: code-signing identity '$SIGN_IDENTITY' not found. Falling back to ad-hoc." >&2
  echo "  Ad-hoc builds lose Keychain 'Always Allow' on every rebuild." >&2
  SIGN_IDENTITY="-"
fi

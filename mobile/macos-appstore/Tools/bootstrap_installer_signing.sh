#!/bin/zsh
set -euo pipefail
export APL_ROTATE_INSTALLER_CERT=1
exec zsh "${0:A:h}/rotate_installer_certificate.sh"

#!/bin/bash
# Installed ON THE NAS at /usr/local/bin/omgstop-nginx-reload, owned root:root,
# mode 755. Not run from your Mac directly—utils/deploy/install-nginx-conf.sh
# invokes it over SSH.
#
# WHY THIS EXISTS
#
# The obvious way to automate the reload is NOPASSWD on the individual commands
# the install needs: cp, chown, chmod, synow3tool, nginx. Do not do that.
# `NOPASSWD: /bin/cp` means "copy any file anywhere as root", which is
# passwordless root with extra steps—it would let anything running as ziad
# overwrite /etc/shadow.
#
# Instead the whole operation lives in one root-owned script with no arguments,
# and sudoers grants passwordless access to exactly that script. ziad cannot
# edit it (root owns it), so the set of things it can do is fixed.
#
# RESIDUAL RISK, STATED PLAINLY: the staging file below is writable by ziad, so
# anything running as ziad can put arbitrary *nginx config* live without the
# password. `nginx -t` stops that from breaking the server, but a valid config
# can still do things you didn't intend, like serving a path you never meant to
# expose. That is a smaller blast radius than passwordless cp, and much smaller
# than your DSM password sitting in a file—but it is not zero.
set -euo pipefail

DOCROOT="/volume1/web/omgstop.org"
STAGE="/tmp/omgstop-user.conf"

# Resolve the Web Station service UUID from the document root rather than
# hardcoding it: recreating the virtual host in DSM issues a new UUID.
CONF=$(grep -ls "root[[:space:]]*\"${DOCROOT}\"" /usr/local/etc/nginx/conf.d/.service.*.conf 2>/dev/null | head -1)
if [ -z "$CONF" ]; then
  echo "No Web Station virtual host found with document root ${DOCROOT}" >&2
  exit 1
fi
UUID=$(basename "$CONF" | sed 's|^\.service\.[0-9a-f-]*\.||; s|\.conf$||')
DEST="/usr/local/etc/nginx/conf.d/${UUID}"

if [ -f "$STAGE" ]; then
  install -d -m 755 "$DEST"
  install -m 644 -o root -g root "$STAGE" "${DEST}/user.conf"
  rm -f "$STAGE"
  echo "installed ${DEST}/user.conf"
else
  echo "no staged config at ${STAGE}; reloading only"
fi

echo "--- regenerating ---"
/usr/syno/bin/synow3tool --gen-all
echo "--- validating ---"
/usr/bin/nginx -t -c /etc/nginx/nginx.conf.run
echo "--- reloading (hup) ---"
/usr/syno/bin/synow3tool --deploy-hup
echo "nginx reloaded"

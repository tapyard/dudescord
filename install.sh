#!/usr/bin/env bash
# Dudescord server installer (ADR 0024).
#
#   curl -fsSL https://github.com/tapyard/dudescord/releases/latest/download/install.sh | sudo bash
#
# Installs the Dudescord server on a Linux machine with systemd and a public
# IPv4 address: the server itself (Galene) under its own system user, a
# certificate from Let's Encrypt for the machine's address (a bare IP address
# is enough, a domain name is optional) renewed by a timer, and the `dudescord`
# command for invites and accounts.  Run it again to update or to change the
# address: accounts and settings stay.
#
# It touches only /opt/dudescord, three units named dudescord*, the command
# /usr/local/bin/dudescord, the system user "dudescord" and — when ufw or
# firewalld is active — the firewall rules for its own ports.
#
# The script works in two phases: without --unpacked it downloads the release
# bundle, checks its checksum and hands over to the install.sh inside the
# bundle, so the code that installs a release is always that release's own.

set -euo pipefail

RELEASES_URL="${DUDESCORD_RELEASES_URL:-https://github.com/tapyard/dudescord/releases}"
DIR=/opt/dudescord
UNIT_DIR=/etc/systemd/system
WRAPPER=/usr/local/bin/dudescord
UDP_RANGE=40000-49999
LETSENCRYPT_STAGING=https://acme-staging-v02.api.letsencrypt.org/directory

ADDRESS=""
PORT=""
ACME_PORT=""
TURN_PORT=""
EMAIL=""
ACME_DIRECTORY=""
VERSION_TAG=""
BUNDLE=""
UNPACKED=""
MODE=install
YES=0
KEEP_DATA=0

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'dudescord: %s\n' "$*" >&2; }
die() {
  printf '\ndudescord: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Dudescord server installer.

  install.sh [options]              install, update, or change the address
  install.sh --uninstall [--yes] [--keep-data]

Options:
  --address <ip or name>   the public address of this machine: its IPv4 address
                           or a domain name that points to it
                           (default: the public IPv4 address, detected)
  --port <n>               HTTPS port (default 443)
  --turn-port <n>          port of the built-in TURN relay, TCP and UDP (default 1194)
  --acme-port <n>          where the certificate proof listens (default 80).
                           Let's Encrypt always connects to port 80: give another
                           port only when a web server of yours owns port 80 and
                           forwards /.well-known/acme-challenge/ to 127.0.0.1:<n>
  --email <address>        e-mail for Let's Encrypt expiry notices (optional)
  --version <tag>          install this release instead of the newest (e.g. v2.2.0)
  --bundle <file>          install from a downloaded bundle instead of the network
  --staging                use Let's Encrypt's staging CA (untrusted test certificates)
  --uninstall              remove the server; asks before deleting accounts
  --yes                    do not ask (with --uninstall)
  --keep-data              with --uninstall: keep accounts, settings and the certificate
USAGE
}

# --- validation: every value below ends up in a systemd unit or a command ---

valid_ipv4() {
  local ip="$1" part
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS=.
  for part in $ip; do
    [ "$((10#$part))" -le 255 ] || return 1
    # no leading zeros: 010.1.1.1 is another address to some parsers
    [ "$part" = "$((10#$part))" ] || return 1
  done
}

valid_name() {
  local name="$1"
  [ "${#name}" -le 253 ] || return 1
  [[ "$name" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || return 1
  # a name, not a number: at least one letter and one dot
  [[ "$name" == *.* && "$name" =~ [a-z] ]] || return 1
  [[ "$name" != *..* ]]
}

valid_address() { valid_ipv4 "$1" || valid_name "$1"; }

valid_port() {
  [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$1" -le 65535 ]
}

valid_email() { [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]]; }

valid_tag() { [[ "$1" =~ ^v[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z.]+)?$ ]]; }

valid_directory() { [[ "$1" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._/-]*)?$ ]]; }

valid_release() { [[ "$1" =~ ^[0-9]{14}-[0-9a-f]{7,40}(-dirty)?$ ]]; }

# --- command line ---

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --address | --port | --turn-port | --acme-port | --email | --version | --bundle | --unpacked | --acme-directory)
      [ "$#" -ge 2 ] && [ -n "$2" ] || die "$1 needs a value (see --help)"
      case "$1" in
      --address) ADDRESS="$2" ;;
      --port) PORT="$2" ;;
      --turn-port) TURN_PORT="$2" ;;
      --acme-port) ACME_PORT="$2" ;;
      --email) EMAIL="$2" ;;
      --version) VERSION_TAG="$2" ;;
      --bundle) BUNDLE="$2" ;;
      --unpacked) UNPACKED="$2" ;;
      --acme-directory) ACME_DIRECTORY="$2" ;;
      esac
      shift 2
      ;;
    --staging)
      ACME_DIRECTORY="$LETSENCRYPT_STAGING"
      shift
      ;;
    --uninstall)
      MODE=uninstall
      shift
      ;;
    --yes)
      YES=1
      shift
      ;;
    --keep-data)
      KEEP_DATA=1
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *) die "unknown option $1 (see --help)" ;;
    esac
  done

  [ -z "$ADDRESS" ] || valid_address "$ADDRESS" ||
    die "--address must be an IPv4 address (203.0.113.5) or a domain name in lower case (chat.example.org)"
  [ -z "$PORT" ] || valid_port "$PORT" || die "--port must be a port number"
  [ -z "$TURN_PORT" ] || valid_port "$TURN_PORT" || die "--turn-port must be a port number"
  [ -z "$ACME_PORT" ] || valid_port "$ACME_PORT" || die "--acme-port must be a port number"
  [ -z "$EMAIL" ] || valid_email "$EMAIL" || die "--email does not look like an e-mail address"
  [ -z "$VERSION_TAG" ] || valid_tag "$VERSION_TAG" || die "--version must be a release tag like v2.2.0"
  [ -z "$ACME_DIRECTORY" ] || valid_directory "$ACME_DIRECTORY" || die "--acme-directory must be an https URL"
}

# What the previous run chose, so that an update needs no options.  Values are
# validated again: the file is root's, but it is still input.  The certificate
# authority is not remembered: --staging is for one test run, and the next
# plain run returns to Let's Encrypt proper.
load_previous() {
  local key value
  [ -f "$DIR/install.conf" ] || return 0
  while IFS='=' read -r key value; do
    case "$key" in
    ADDRESS) [ -n "$ADDRESS" ] || ! valid_address "$value" || ADDRESS="$value" ;;
    PORT) [ -n "$PORT" ] || ! valid_port "$value" || PORT="$value" ;;
    TURN_PORT) [ -n "$TURN_PORT" ] || ! valid_port "$value" || TURN_PORT="$value" ;;
    ACME_PORT) [ -n "$ACME_PORT" ] || ! valid_port "$value" || ACME_PORT="$value" ;;
    EMAIL) [ -n "$EMAIL" ] || ! valid_email "$value" || EMAIL="$value" ;;
    esac
  done <"$DIR/install.conf"
}

render_conf() {
  printf 'ADDRESS=%s\nPORT=%s\nTURN_PORT=%s\nACME_PORT=%s\n' "$ADDRESS" "$PORT" "$TURN_PORT" "$ACME_PORT"
  [ -z "$EMAIL" ] || printf 'EMAIL=%s\n' "$EMAIL"
}

# --- the machine ---

machine_arch() {
  case "$(uname -m)" in
  x86_64 | amd64) say amd64 ;;
  aarch64 | arm64) say arm64 ;;
  *) die "this machine is $(uname -m); Dudescord is built for x86-64 and arm64" ;;
  esac
}

check_machine() {
  [ "$(uname -s)" = Linux ] || die "the server runs on Linux; this is $(uname -s)"
  [ "${EUID:-$(id -u)}" -eq 0 ] ||
    die "run this as root: it creates a system user and writes $DIR and $UNIT_DIR. Nothing was changed."
  [ -d /run/systemd/system ] || die "this machine does not run systemd, which the installer needs. Nothing was changed."
  local tool
  for tool in curl tar sha256sum runuser useradd install; do
    command -v "$tool" >/dev/null 2>&1 ||
      die "the command '$tool' is missing; install it with the system's package manager and run this again. Nothing was changed."
  done
  machine_arch >/dev/null
}

# The public IPv4 address as the internet sees it: asked from three services,
# the first valid answer wins.
detect_address() {
  local url answer
  for url in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
    answer="$(curl -4 -fsS --max-time 10 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    if valid_ipv4 "$answer"; then
      say "$answer"
      return 0
    fi
  done
  return 1
}

# The IPv4 address the TURN relay announces: the address itself, or what the
# name resolves to.
relay_address() {
  local address="$1" resolved
  if valid_ipv4 "$address"; then
    say "$address"
    return 0
  fi
  resolved="$(getent ahostsv4 "$address" 2>/dev/null | awk '{print $1; exit}' || true)"
  valid_ipv4 "$resolved" || return 1
  say "$resolved"
}

# Is something listening?  $1: t (TCP) or u (UDP).  Without `ss` the answer is
# "no": the service or the certificate step will say so themselves.
port_busy() {
  command -v ss >/dev/null 2>&1 || return 1
  [ -n "$(ss -H -l"$1"n "sport = :$2" 2>/dev/null)" ]
}

# --- phase 1: fetch the bundle and hand over to its own installer ---

fetch_and_hand_over() {
  local arch name base tmp
  arch="$(machine_arch)"
  name="dudescord-server-linux-$arch.tar.gz"
  tmp="$(mktemp -d /tmp/dudescord-install.XXXXXXXX)"
  if [ -n "$BUNDLE" ]; then
    [ -f "$BUNDLE" ] || die "--bundle: $BUNDLE is not a file"
    step "Unpacking $BUNDLE"
    cp "$BUNDLE" "$tmp/$name"
  else
    if [ -n "$VERSION_TAG" ]; then
      base="$RELEASES_URL/download/$VERSION_TAG"
    else
      base="$RELEASES_URL/latest/download"
    fi
    step "Downloading the Dudescord server ($arch)"
    curl -fL --retry 3 --connect-timeout 20 --progress-bar -o "$tmp/$name" "$base/$name" ||
      die "could not download $base/$name. Nothing was changed."
    curl -fsSL --retry 3 --connect-timeout 20 -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" ||
      die "could not download $base/SHA256SUMS. Nothing was changed."
    (cd "$tmp" && grep -F "  $name" SHA256SUMS | sha256sum -c --status -) ||
      die "the downloaded bundle does not match its checksum; try again. Nothing was changed."
  fi
  mkdir "$tmp/bundle"
  tar -xzf "$tmp/$name" -C "$tmp/bundle" --no-same-owner
  rm -f "$tmp/$name"
  [ -f "$tmp/bundle/install.sh" ] || die "the bundle has no install.sh: it is not a Dudescord server bundle"
  exec bash "$tmp/bundle/install.sh" "$@" --unpacked "$tmp/bundle" </dev/null
}

# --- units ---

render_unit() {
  cat <<UNIT
[Unit]
Description=Dudescord (Galene)
After=network-online.target
Wants=network-online.target

[Service]
User=dudescord
Group=dudescord
ExecStart=$DIR/current/galene -http :$PORT -static $DIR/current/static -data $DIR/data -groups $DIR/groups -turn $RELAY:$TURN_PORT -udp-range $UDP_RANGE
Restart=always
RestartSec=3
MemoryMax=256M
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=$DIR/data $DIR/groups
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT
}

# The proof listens on every interface on port 80, or on loopback only when
# the host's own web server forwards to another port.
render_cert_unit() {
  local options="--data $DIR/data --id $ADDRESS --http-port $ACME_PORT"
  [ "$ACME_PORT" = 80 ] || options="$options --http-addr 127.0.0.1"
  [ -z "$ACME_DIRECTORY" ] || options="$options --directory $ACME_DIRECTORY"
  [ -z "$EMAIL" ] || options="$options --email $EMAIL"
  cat <<UNIT
[Unit]
Description=Dudescord certificate (Let's Encrypt)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=dudescord
Group=dudescord
ExecStart=$DIR/current/dudescordctl cert $options
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=$DIR/data
UNIT
}

# Four times a day: a certificate for an IP address lives six days and is
# renewed at half of that, so a failed attempt has many more before it matters.
render_cert_timer() {
  cat <<'UNIT'
[Unit]
Description=Renew the Dudescord certificate

[Timer]
OnCalendar=*-*-* 00/6:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
UNIT
}

# `dudescord update` and `dudescord uninstall` are this installer; everything
# else is the helper of the current release.
render_wrapper() {
  cat <<WRAPPER
#!/usr/bin/env bash
# Dudescord server command (installed by the Dudescord installer).
set -euo pipefail
case "\${1:-}" in
update)
  shift
  exec bash $DIR/current/install.sh "\$@"
  ;;
uninstall)
  shift
  exec bash $DIR/current/install.sh --uninstall "\$@"
  ;;
*) exec $DIR/current/dudescordctl "\$@" ;;
esac
WRAPPER
}

# Installs stdin as a file when it differs; says what it did.
install_file() {
  local path="$1" mode="$2" body
  body="$(cat)"
  if [ -f "$path" ] && [ "$body" = "$(cat "$path")" ]; then
    return 0
  fi
  printf '%s\n' "$body" >"$path.new"
  chmod "$mode" "$path.new"
  mv "$path.new" "$path"
  say "installed $path"
}

# --- firewall ---

firewall_ports_tcp() {
  [ "$ACME_PORT" != 80 ] || printf '80 '
  printf '%s %s\n' "$PORT" "$TURN_PORT"
}

open_firewall() {
  local port
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    step "Opening the ports in ufw"
    for port in $(firewall_ports_tcp); do
      ufw allow "$port/tcp" comment dudescord >/dev/null || warn "ufw allow $port/tcp failed"
    done
    ufw allow "$TURN_PORT/udp" comment dudescord >/dev/null || warn "ufw allow $TURN_PORT/udp failed"
    ufw allow "${UDP_RANGE/-/:}/udp" comment dudescord >/dev/null || warn "ufw allow ${UDP_RANGE/-/:}/udp failed"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    step "Opening the ports in firewalld"
    for port in $(firewall_ports_tcp); do
      firewall-cmd --quiet --permanent --add-port="$port/tcp" || warn "firewall-cmd --add-port=$port/tcp failed"
    done
    firewall-cmd --quiet --permanent --add-port="$TURN_PORT/udp" || warn "firewall-cmd --add-port=$TURN_PORT/udp failed"
    firewall-cmd --quiet --permanent --add-port="$UDP_RANGE/udp" || warn "firewall-cmd --add-port=$UDP_RANGE/udp failed"
    firewall-cmd --quiet --reload || warn "firewall-cmd --reload failed"
  fi
}

ports_summary() {
  local tcp
  tcp="$(firewall_ports_tcp)"
  say "  TCP ${tcp// /, }    UDP $TURN_PORT, $UDP_RANGE"
}

# --- releases ---

# Keeps the three newest releases; never the one in use.
prune_releases() {
  local old total=0 index=0
  cd "$DIR/releases"
  for old in [0-9]*-*/; do
    [ -d "$old" ] && total=$((total + 1))
  done
  for old in [0-9]*-*/; do
    [ -d "$old" ] || continue
    index=$((index + 1))
    [ "$index" -le "$((total - 3))" ] || continue
    [ "$old" -ef "$DIR/current" ] && continue
    rm -rf "$old" || warn "could not remove the old release $DIR/releases/$old"
  done
  cd /
}

# --- phase 2: install the unpacked release ---

install_release() {
  local release bundle_arch dest ctl service_active=0

  local part
  for part in RELEASE ARCH galene dudescordctl static/index.html; do
    [ -f "$UNPACKED/$part" ] || die "the bundle is incomplete: no $part"
  done
  release="$(head -n 1 "$UNPACKED/RELEASE")"
  valid_release "$release" || die "the bundle names its release strangely: refusing to install it"
  bundle_arch="$(head -n 1 "$UNPACKED/ARCH")"
  [ "$bundle_arch" = "$(machine_arch)" ] ||
    die "this bundle is for $bundle_arch and this machine is $(machine_arch)"

  # A server put here by the developers' deploy tool is not ours to change.
  if [ -e "$DIR/current" ] && [ ! -f "$DIR/install.conf" ]; then
    die "$DIR holds a Dudescord server that this installer did not install (deployed from the source repository). Nothing was changed."
  fi
  ! systemctl is-active --quiet dudescord.service 2>/dev/null || service_active=1

  load_previous
  PORT="${PORT:-443}"
  TURN_PORT="${TURN_PORT:-1194}"
  ACME_PORT="${ACME_PORT:-80}"
  if [ -z "$ADDRESS" ]; then
    step "Finding this machine's public address"
    ADDRESS="$(detect_address)" ||
      die "could not find this machine's public IPv4 address. Run again with --address <the address>. Nothing was changed."
    say "$ADDRESS"
  fi
  RELAY="$(relay_address "$ADDRESS")" ||
    die "$ADDRESS does not resolve to an IPv4 address. Create an A record that points to this machine, wait until it is visible, and run this again. Nothing was changed."

  if [ "$service_active" -eq 0 ]; then
    ! port_busy t "$PORT" ||
      die "TCP port $PORT is in use by another program. Free it, or choose another port with --port (the address then becomes https://$ADDRESS:<port>). Nothing was changed."
    if port_busy t "$TURN_PORT" || port_busy u "$TURN_PORT"; then
      die "port $TURN_PORT is in use by another program. Choose another one for the TURN relay with --turn-port. Nothing was changed."
    fi
  fi
  if port_busy t "$ACME_PORT"; then
    if [ "$ACME_PORT" = 80 ]; then
      die "TCP port 80 is in use by another program, and Let's Encrypt proves the address there. Stop that program, or keep it and make it forward /.well-known/acme-challenge/ to 127.0.0.1:<n>, then run again with --acme-port <n>. Nothing was changed."
    fi
    die "TCP port $ACME_PORT (--acme-port) is in use by another program. Nothing was changed."
  fi

  step "Installing release $release to $DIR"
  id -u dudescord >/dev/null 2>&1 ||
    useradd --system --home-dir "$DIR/data" --shell /usr/sbin/nologin dudescord
  install -d -m 0755 -o root -g root "$DIR" "$DIR/releases"
  install -d -m 0750 -o dudescord -g dudescord "$DIR/data" "$DIR/groups"

  dest="$DIR/releases/$release"
  if [ ! -d "$dest" ]; then
    # copied beside its final place and renamed: a release directory is
    # either complete or absent
    rm -rf "$DIR/releases/.incoming"
    cp -R "$UNPACKED" "$DIR/releases/.incoming"
    chown -R root:root "$DIR/releases/.incoming"
    chmod -R u=rwX,go=rX "$DIR/releases/.incoming"
    chmod 0755 "$DIR/releases/.incoming/galene" "$DIR/releases/.incoming/dudescordctl"
    mv "$DIR/releases/.incoming" "$dest"
  fi
  ctl="$dest/dudescordctl"

  # server.json (root only) holds the admin password; data/ belongs to the
  # service user, so its files are created by that user and not by root.
  "$ctl" init --address "$ADDRESS" --port "$PORT"
  "$ctl" admin-config | runuser -u dudescord -- "$ctl" init-data

  render_conf | install_file "$DIR/install.conf" 0600
  render_unit | install_file "$UNIT_DIR/dudescord.service" 0644
  render_cert_unit | install_file "$UNIT_DIR/dudescord-cert.service" 0644
  render_cert_timer | install_file "$UNIT_DIR/dudescord-cert.timer" 0644
  render_wrapper | install_file "$WRAPPER" 0755

  ln -sfn "$dest" "$DIR/current"
  systemctl daemon-reload

  open_firewall

  step "Getting the certificate for $ADDRESS from Let's Encrypt"
  if ! systemctl start dudescord-cert.service; then
    journalctl -u dudescord-cert.service -n 25 --no-pager -o cat >&2 || true
    die "no certificate yet, so the server was not started; the reason is in the lines above. Most often Let's Encrypt cannot reach http://$ADDRESS/ (TCP port 80) from the internet: open that port in the provider's firewall or security group, check the address, and run the installer again."
  fi
  systemctl enable --quiet --now dudescord-cert.timer

  step "Starting the server"
  systemctl enable --quiet dudescord.service
  systemctl restart dudescord.service
  if ! "$ctl" wait-healthy --seconds 40; then
    journalctl -u dudescord.service -n 30 --no-pager -o cat >&2 || true
    die "the server does not answer; its last log lines are above. Earlier releases, if any, are in $DIR/releases."
  fi
  prune_releases
  # the download directory of phase 1, and nothing else
  case "$UNPACKED" in
  /tmp/dudescord-install.*/bundle) rm -rf "$(dirname "$UNPACKED")" ;;
  esac

  # An empty server ends every run with a link to send; a server that has
  # accounts is only reported on.
  local link
  link="$("$ctl" first-invite)"
  say ""
  if [ -n "$link" ]; then
    say "Dudescord is running. Send this link to your friends: everyone who opens it"
    say "chooses a name and a password. It works for any number of people; a new link"
    say "lasts 7 days."
    say ""
    say "  $link"
  else
    say "Dudescord is updated and running."
  fi
  say ""
  "$ctl" status
  say ""
  say "  dudescord invite            a new invite link"
  say "  dudescord users             who has an account"
  say "  dudescord status            is everything all right"
  say "  dudescord update            install the newest release"
  say ""
  say "These ports must be reachable from the internet (the provider's firewall or"
  say "security group, if there is one):"
  ports_summary
}

# --- uninstall ---

uninstall() {
  [ "${EUID:-$(id -u)}" -eq 0 ] || die "run this as root"
  if [ -e "$DIR/current" ] && [ ! -f "$DIR/install.conf" ]; then
    die "$DIR holds a Dudescord server that this installer did not install. Nothing was changed."
  fi
  if [ "$KEEP_DATA" -eq 0 ] && [ "$YES" -eq 0 ]; then
    if [ -t 0 ]; then
      local answer
      printf 'This removes the server with every account, the invites and the chat history.\nType "yes" to go on: '
      read -r answer
      [ "$answer" = yes ] || die "not removed"
    else
      die "this removes every account; say so with --yes, or keep them with --keep-data"
    fi
  fi
  systemctl disable --quiet --now dudescord-cert.timer dudescord.service 2>/dev/null || true
  systemctl stop dudescord-cert.service 2>/dev/null || true
  rm -f "$UNIT_DIR/dudescord.service" "$UNIT_DIR/dudescord-cert.service" "$UNIT_DIR/dudescord-cert.timer" "$WRAPPER"
  systemctl daemon-reload
  if [ "$KEEP_DATA" -eq 1 ]; then
    rm -rf "$DIR/releases" "$DIR/current"
    say "Dudescord is removed. Accounts, settings and the certificate stay in $DIR;"
    say "the installer picks them up if you install again."
  else
    rm -rf "$DIR"
    ! id -u dudescord >/dev/null 2>&1 || userdel dudescord 2>/dev/null || warn "could not remove the user dudescord"
    say "Dudescord is removed."
  fi
  say "Firewall rules, if the installer added any, are still there (comment or port list: dudescord)."
}

main() {
  parse_args "$@"
  if [ "$MODE" = uninstall ]; then
    uninstall
    return
  fi
  check_machine
  if [ -z "$UNPACKED" ]; then
    fetch_and_hand_over "$@"
  fi
  [ -d "$UNPACKED" ] || die "--unpacked: $UNPACKED is not a directory"
  install_release
}

# Sourced by the tests for its functions; run otherwise.  Everything is inside
# functions and main is the last line, so a script cut short by a broken
# download does nothing.
if [ "${DUDESCORD_INSTALL_SOURCED:-}" != 1 ]; then
  main "$@"
fi

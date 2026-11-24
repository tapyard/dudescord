# Dudescord server — a guide for agents

You are an AI agent, and a person asked you to install or look after a Dudescord server. This
page is written for you: what to run, in what order, what each answer looks like, and what to
hand back to the person. People read [README.md](README.md) instead.

On a server that already runs Dudescord this file is `/opt/dudescord/current/AGENTS.md`.

## What it is

Dudescord is voice, video, screen sharing and chat for a group of friends: one server, one
room, up to 20 people. The server is one small program ([Galene](https://galene.org)) under
systemd, with a certificate from Let's Encrypt for the machine's bare IP address — no domain
name is needed. People join from a browser or the desktop app through an invite link.

A finished install is: the service `dudescord` running, `https://<address>` answering with a
valid certificate, and an invite link in the person's hands.

## Rules

- **Nothing here needs an answer.** Every command runs unattended. The one destructive command,
  `dudescord uninstall`, must be given `--yes` or `--keep-data`: without them it refuses — or,
  on a terminal, asks and waits. Never run it bare.
- **Run as root** (or with `sudo`). Every command below needs it.
- **Read answers with `--json`.** The commands that ask the server something (the first table
  under "Commands") then print one JSON object on standard output and nothing else there. The
  installer and the three commands that run it — `apply`, `update`, `uninstall` — print text
  for people and take no `--json`: read their exit status, then `dudescord status --json`.
- **Exit status**, everywhere: `0` done, `1` failed, `2` the command line is wrong. A failure
  is words on standard error starting with `dudescord:` — they say what is wrong and what to
  do; pass them on to the person as they are.
- **Settings live in one file**, `/opt/dudescord/dudescord.conf`. To change something, edit
  that file and run `dudescord apply`. Do not edit the systemd units, `server.json`, or anything
  under `data/` and `groups/` — the installer rewrites the first and the server owns the rest.
- **Never print, copy or send the admin password** (`/opt/dudescord/server.json`). Nothing you
  are asked to do needs it: the `dudescord` command uses it by itself.
- **An invite link lets anyone who has it create an account.** Give it to the person who asked
  and to nobody else; do not post it into an issue, a log or a chat you were not told to use.
- **Do not retry a failed certificate in a loop.** Let's Encrypt gives one address five
  certificates a week. A failed install tells you why; fix the cause (almost always TCP port 80
  closed in the provider's firewall), then run the installer once more.
- **You cannot open the provider's firewall** (security groups, the hosting panel). The
  installer opens `ufw` or `firewalld` on the machine; the rest is the person's: tell them the
  ports (below).
- A server on a home computer is not supported: it needs a public IPv4 address.

## What you need from the person

- The machine: a VPS with Linux and systemd (Ubuntu, Debian and the like), x86-64 or arm64,
  a public IPv4 address, 1 core and 512 MB are enough — and root access to it.
- Optional: a domain name that already points to the machine (an `A` record). Without one the
  address is the IP itself.
- The name they want in the room, to make them the owner (step 5).

## Install

### 1. Check — changes nothing

```sh
curl -fsSL https://github.com/tapyard/dudescord/releases/latest/download/install.sh | bash -s -- --check
```

Exit status `0` and `Ready: …` mean that an install will get through its checks:

```
Ready: Dudescord is not installed here; a run now installs it.
Nothing was changed.

  address      https://203.0.113.5
  ADDRESS      203.0.113.5
  PORT         443
  TURN_PORT    1194
  ACME_PORT    80
  EMAIL
  settings     /opt/dudescord/dudescord.conf

These ports must be reachable from the internet (the provider's firewall or
security group, if there is one — the installer cannot open that one):
  TCP 80, 443, 1194    UDP 1194, 40000-49999
```

Exit status `1` names what is in the way. The usual cases:

| The message says | What to do |
|---|---|
| `TCP port 443 is in use by another program` | pick another: `--port 8443` (the address becomes `https://<address>:8443`) |
| `port 1194 is in use` | `--turn-port 3479` |
| `TCP port 80 is in use by another program` | the machine has a web server. Keep it: make it forward `/.well-known/acme-challenge/` to `127.0.0.1:8089` (nginx: `location ^~ /.well-known/acme-challenge/ { proxy_pass http://127.0.0.1:8089; proxy_set_header Host $host; }`), reload it, and add `--acme-port 8089` |
| `could not find this machine's public IPv4 address` | `--address <the address>` |
| `… does not resolve to an IPv4 address` | the domain's `A` record is missing or not visible yet |
| `the command 'ss' is missing` (or `curl`, `tar`, …) | install the package (`iproute2` for `ss`) with the system's package manager |
| `holds a Dudescord server that this installer did not install` | leave it alone and tell the person |

The check cannot see the provider's firewall. If port 80 is closed there, the install itself
fails at the certificate step and says so.

### 2. Settings — only if the defaults do not fit

Options on the command line are enough for a one-off (`--address`, `--port`, `--turn-port`,
`--acme-port`, `--email`). Or write a file in the shape of the settings file and pass it:

```sh
cat > /root/dudescord.conf <<'EOF'
ADDRESS=chat.example.org
PORT=443
EOF
```

and add `--config /root/dudescord.conf` to the commands of steps 1 and 3. An option overrides
the file. Either way the installer writes the result to `/opt/dudescord/dudescord.conf`, and
that file is what counts afterwards.

### 3. Install

```sh
curl -fsSL https://github.com/tapyard/dudescord/releases/latest/download/install.sh | bash
```

with the same options as the check (after `bash -s --`). It takes about a minute. Lines that
start with `==>` are its steps. Exit status `0` means the server runs; the output ends with
the invite link, a status report and the ports. Running it again is safe: it updates and
keeps the accounts.

If it stops at `no certificate yet, so the server was not started`: Let's Encrypt could not
reach `http://<address>/` on TCP port 80. Ask the person to open the ports in the provider's
firewall, then run the same command again — it continues where it stopped.

### 4. Verify

```sh
dudescord status --json
```

```json
{"healthy":true,"url":"https://203.0.113.5","address":"203.0.113.5","port":443,"turnPort":1194,"acmePort":80,"version":"2.3.0","commit":"abc1234","service":"active","certificate":{"valid":true,"notAfter":"2026-11-30T23:10:00Z","daysLeft":6.6},"accounts":0,"owners":[],"connected":0,"settingsFile":"/opt/dudescord/dudescord.conf","problems":[]}
```

`healthy` is `true` when the service runs, the certificate is one a browser accepts — from a
trusted authority, for this address, in date — and the server answers. Otherwise the exit
status is `1`, the JSON is still printed, and `problems` lists, in words, what is wrong and
where to look — also right after an install that failed. (The one case without JSON: the
server's own `server.json` cannot be loaded — missing, unreadable, malformed or incomplete: not
installed, not run as root, or damaged. Then there are only the words on standard error.) The
certificate is judged by this machine's own root certificates; the check from outside, below,
is the one that speaks for a visitor's browser. From outside the machine, `curl -sS -o /dev/null -w '%{http_code}\n' <url>/` must print
`200` without a certificate error; if it works on the machine and not from outside, the
provider's firewall is closed.

### 5. The invite and the owner

```sh
dudescord invite --json
```

```json
{"link":"https://203.0.113.5/#invite=AbCdEfGhIjK","token":"AbCdEfGhIjK","expires":"2026-12-01T10:00:00Z"}
```

Everyone who opens the link chooses a name and a password. It works for any number of people
and lasts 7 days (`--days N` for another length).

The **owner** is an account that also gets a "Server" section in the app's settings: invites
and accounts without a terminal. Ask the person to open the link and register first, then:

```sh
dudescord owner '<their name>' --json
```

```json
{"name":"Alice","owner":true,"created":false}
```

It takes effect when they join the room next (a reload of the page is enough). A name with a
colon (`:`) in it cannot be an owner; any other name can. If the person
gave you a name and a password and wants the account made for them, create it — the password
goes on standard input, never on the command line:

```sh
printf '%s\n' "$PASSWORD" | dudescord owner '<their name>' --create --json
```

`"created":false` after `--create` means the account already existed: it is an owner now and
its password was not changed. `dudescord owner '<name>' --remove` takes the permission away.

An owner can do everything to the room that the room's API allows — every account, every
password, the invites, the room's own settings — with their own name and password. Make an
owner only of the person who asked, or of whom they name.

### 6. Hand over

Tell the person:

- the address (`url`) and the invite link, and that the link is for their friends too;
- that they are the owner and where the "Server" section is (the gear → "Server");
- the ports that must be open in the provider's firewall, if it has one: TCP 80, TCP `PORT`,
  TCP and UDP `TURN_PORT`, UDP 40000–49999. If people join but do not hear each other, it is
  these;
- that the desktop apps (Windows, macOS) are linked at the bottom of the server's login page.

## The settings file

`/opt/dudescord/dudescord.conf` — `KEY=value` lines and `#` comments, no quotes. The installer
writes it with a comment above every key.

| Key | Default | Meaning |
|---|---|---|
| `ADDRESS` | the machine's public IPv4 address | the address in every invite link and in the certificate: an IPv4 address or a lower-case domain name that points to the machine |
| `PORT` | `443` | HTTPS port of the site (TCP). Never `80` |
| `TURN_PORT` | `1194` | the built-in relay, TCP and UDP. Not `80`, not inside 40000–49999 |
| `ACME_PORT` | `80` | where the certificate proof listens. Another number only behind a web server that forwards `/.well-known/acme-challenge/` to `127.0.0.1:<this>` |
| `EMAIL` | empty | e-mail for Let's Encrypt's notices (optional) |

To change a setting:

```sh
dudescord config --json          # {"file":"/opt/dudescord/dudescord.conf","settings":{"ADDRESS":"…","PORT":443,…},"apply":"dudescord apply"}
# edit the file
dudescord apply                  # checks the new values first, then rewrites the units and restarts
```

`apply` stops before changing anything when a value is wrong, a key is unknown (the message
names the line) or a port is taken. It restarts the server: everyone drops for a few seconds
and reconnects by themselves. After a change of `ADDRESS` or `PORT` old invite links point at
the old address: make a new one. Accounts stay.

## Commands

All as root. Everything in the first table takes `--json`; the second table's commands run
the installer and print text.

| Command | Does | `--json` answer |
|---|---|---|
| `dudescord status` | the report of step 4; exit status 1 when not healthy | see step 4 |
| `dudescord config` | the settings file and its values | `{"file","settings":{…},"apply"}` |
| `dudescord invite [--days N]` | a new invite link (7 days) | `{"link","token","expires"}` |
| `dudescord invites` | the live invites | `{"invites":[{"link","token","expires"}]}` |
| `dudescord revoke <token or link>` | the link stops working; accounts made with it stay | `{"token","revoked":true}` |
| `dudescord users` | the accounts | `{"users":[{"name","owner"}]}` |
| `dudescord owner <name> [--create\|--remove]` | makes an account the owner (step 5) | `{"name","owner","created"}` |
| `dudescord reset-password <name>` | sets a new random password and prints it once — give it to that person only | `{"name","password"}` |
| `dudescord remove <name> [--restart]` | removes an account; `--restart` also drops everyone connected now | `{"name","removed":true,"restarted"}` |

| Command | Does |
|---|---|
| `dudescord apply` | applies the settings file (restarts the server) |
| `dudescord update` | installs the newest release; accounts and settings stay (restarts the server) |
| `dudescord uninstall --yes` | removes everything, accounts included |
| `dudescord uninstall --keep-data` | removes the programs, keeps accounts, settings and the certificate for a later install |

Removing an account or resetting a password acts when that person joins next; someone who is
connected stays until they disconnect.

## When something is wrong

Start with `dudescord status --json` and read `problems`.

| Symptom | Where to look | Usual cause |
|---|---|---|
| the install stops at the certificate | the lines it printed above the message | TCP port 80 closed at the provider, or the address is not this machine's |
| `certificate` not `valid`, or the browser says it expired | `journalctl -u dudescord-cert -n 50 --no-pager` | port 80 was closed after the install; the certificate for an IP address lives six days and is renewed every three, so this shows within days |
| `… earlier orders for a certificate did not finish … waits until …` | the message itself | orders whose result was lost (a full disk, a broken connection) are paced to stay inside Let's Encrypt's limit. Fix the cause (`df -h /opt/dudescord/data`) and wait; do not delete files to force it unless the person says so |
| `service` is not `active` | `journalctl -u dudescord -n 50 --no-pager` | a port was taken by another program since the install |
| people join but hear nothing | — | UDP 40000–49999 or `TURN_PORT` closed at the provider |
| a command says `run this as root` | — | use `sudo` |

An update that does not come up is not rolled back by itself. Back to the previous release:

```sh
ls /opt/dudescord/releases
ln -sfn /opt/dudescord/releases/<previous> /opt/dudescord/current && systemctl restart dudescord
```

## What is where

| Path | What | Yours to change? |
|---|---|---|
| `/opt/dudescord/dudescord.conf` | the settings | yes, then `dudescord apply` |
| `/opt/dudescord/groups/main.json` | the accounts (password hashes) | no — use the commands; copy it for a backup |
| `/opt/dudescord/data/` | the certificate, invites, the server's config | no |
| `/opt/dudescord/server.json` | the admin password | no; never print it |
| `/opt/dudescord/releases/`, `current` | the installed releases | no |
| `dudescord.service`, `dudescord-cert.service`, `dudescord-cert.timer` | the units | no — rewritten by every install, update and apply |

A backup is `server.json`, `dudescord.conf`, `data/` and `groups/`. To move to another
machine: install there, copy `groups/main.json` over the new one,
`chown dudescord:dudescord` it and `systemctl restart dudescord`; then make new invite links.

## From your own machine, over ssh

The same commands, quoted once:

```sh
ssh root@203.0.113.5 'curl -fsSL https://github.com/tapyard/dudescord/releases/latest/download/install.sh | bash -s -- --check'
ssh root@203.0.113.5 'curl -fsSL https://github.com/tapyard/dudescord/releases/latest/download/install.sh | bash'
ssh root@203.0.113.5 'dudescord status --json'
```

As a user with `sudo`: put `sudo` before `bash` and before `dudescord`.

# Dudescord

Voice, video, screen sharing and chat for a group of friends — on your own server.

[По-русски](README.ru.md)

- **One server, one room.** You send a link; each friend picks a name and a password. No
  accounts anywhere else, no phone numbers, nothing leaves your server.
- **Works in a browser** on a computer or a phone. The desktop app (Windows, macOS) is the same
  client in its own window, plus global hotkeys (push-to-talk, mute, deafen) and a game
  overlay with your friends' cameras.
- **Tiny.** The server is [Galene](https://galene.org); it uses a few dozen megabytes of memory
  and fits beside other things on the cheapest VPS.
- Russian and English interface.

## Your own server in five minutes

You need a VPS (or any Linux machine) with:

- Linux with systemd — Ubuntu, Debian and the like; x86-64 or arm64;
- a public IPv4 address;
- root access;
- 1 CPU core and 512 MB of memory are enough.

A domain name is **not** needed: the server gets a certificate for its bare IP address.

Log in to the machine and run:

```sh
curl -fsSL https://github.com/tapyard/dudescord/releases/latest/download/install.sh | sudo bash
```

In about a minute it prints an invite link:

```
Dudescord is running. Send this link to your friends: everyone who opens it
chooses a name and a password. It works for any number of people; a new link
lasts 7 days.

  https://203.0.113.5/#invite=…
```

Open it yourself first, pick a name and a password — you are in the room. Send the same link
to your friends. The link to the apps is at the bottom of the login page of your server.

### Ports

If your provider has a firewall or "security groups" in its control panel, these must be let
in. (`ufw` and `firewalld` on the machine itself are opened by the installer.)

| Port | For |
|---|---|
| TCP 80 | Let's Encrypt checks the address here when it issues or renews the certificate |
| TCP 443 | the site and the connection of every client |
| TCP and UDP 1194 | the relay for people whose network blocks direct media |
| UDP 40000–49999 | voice and video |

### With a domain name

Point an `A` record at the machine, wait until it resolves, then:

```sh
curl -fsSL https://github.com/tapyard/dudescord/releases/latest/download/install.sh | sudo bash -s -- --address chat.example.org
```

### When the ports are taken

- Port 443 is busy: `--port 8443` — the address becomes `https://203.0.113.5:8443`.
- Port 1194 is busy (OpenVPN, say): `--turn-port 3479`.
- Port 80 is busy with your own web server: keep it, make it forward
  `/.well-known/acme-challenge/` to `127.0.0.1:8089`, and add `--acme-port 8089`. For nginx:

  ```nginx
  location ^~ /.well-known/acme-challenge/ {
      proxy_pass http://127.0.0.1:8089;
      proxy_set_header Host $host;
  }
  ```

Options are remembered: later runs and updates need none of them.

## Running it

Everything is one command on the server, as root:

```sh
dudescord invite                  # a new invite link, valid 7 days
dudescord invite --days 30
dudescord invites                 # the live links
dudescord revoke <link>           # the link stops working; accounts made with it stay
dudescord users                   # who has an account
dudescord reset-password <name>   # prints a new password for someone who forgot theirs
dudescord remove <name>           # removes an account
dudescord remove <name> --restart # …and drops everyone connected right now
dudescord status                  # address, version, certificate, who is connected
dudescord update                  # the newest release; accounts and settings stay
dudescord uninstall               # removes everything (asks first)
```

An update restarts the server: everyone drops for a few seconds and reconnects by themselves.

**The address changed** (a new IP, or you got a domain): `dudescord update --address <new>`.
Accounts stay; people open the new address and log in with the same name and password. Old
invite links point at the old address — make a new one.

**Backup**: `/opt/dudescord/server.json`, `/opt/dudescord/data/` and `/opt/dudescord/groups/`
are all there is — accounts, invites, the certificate. The accounts are one file,
`/opt/dudescord/groups/main.json`: to move to another machine, install there, copy that file
over the new one, `chown dudescord:dudescord` it and `systemctl restart dudescord`.

## What the installer does

It is one shell script — [read it](install.sh) before you run it. It:

- downloads the release bundle from this page and checks its checksum;
- creates the system user `dudescord` and the directory `/opt/dudescord`;
- gets a certificate from Let's Encrypt and renews it by a timer (a certificate for an IP
  address lives six days and is renewed every three);
- installs three systemd units — `dudescord.service`, `dudescord-cert.service`,
  `dudescord-cert.timer` — and the command `/usr/local/bin/dudescord`;
- opens its ports in `ufw` or `firewalld` if one of them is active.

Nothing else on the machine is touched. The server runs as its own unprivileged user with a
256 MB memory cap. The admin password is generated on the machine and stays in
`/opt/dudescord/server.json`, readable by root only.

## If something goes wrong

- **"no certificate yet"** during the install — Let's Encrypt could not reach port 80. Open TCP
  port 80 in the provider's firewall and run the command again; it continues where it stopped.
- **People join but do not hear each other** — UDP 40000–49999 or port 1194 is blocked by the
  provider's firewall.
- **The browser says the certificate has expired** — `dudescord status`, then
  `journalctl -u dudescord-cert` shows why the renewal fails (almost always port 80).
- **Is it running?** — `dudescord status`, `journalctl -u dudescord -n 50`.

## Good to know

- One room for up to 20 people. No channels, roles or moderation: it is a room for friends.
- A server on a home computer is not supported: it needs a public IP address and port
  forwarding, and most home connections have neither. The cheapest VPS does.
- Tested on Ubuntu 26.04 (x86-64). Other systemd distributions should work; tell us if one does
  not.
- The apps: macOS on Apple Silicon (notarized) and Windows x64 (not signed — Windows shows
  "Windows protected your PC": "More info" → "Run anyway").

## Licence

MIT — see [LICENSE](LICENSE). Built on [Galene](https://galene.org) by Juliusz Chroboczek and
contributors (MIT); other components are listed in [NOTICE.md](NOTICE.md).

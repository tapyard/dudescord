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

  https://203.0.113.5:27413/#invite=…
```

Open it yourself first, pick a name and a password — you are in the room. Send the same link
to your friends. The link to the apps is at the bottom of the login page of your server.

Then make yourself the owner, so that invites and accounts are in the app's settings and you
need the terminal no more: `sudo dudescord owner <your name>`, and reload the page.

### With an AI agent

Give your coding agent (Claude Code, Codex, Cursor, …) access to the machine and this:

> Install a Dudescord server on my VPS, following
> https://github.com/tapyard/dudescord/blob/main/AGENTS.md. My name in the room will be …

[AGENTS.md](AGENTS.md) is written for agents: the checks, the commands in order, what every
answer looks like, and what to tell you at the end. Nothing in it needs an answer from a
person, the server's answers come as JSON with `--json`, and the settings are one file.

### From the desktop app

The app can install the server for you: on its first page choose "Create your own server",
enter the machine's address and the root password your provider sent, and your name and
password for the room.

### Ports

The server does not sit on the usual ports. The installer picks two of the machine's own,
between 20000 and 31999 — one for the site, one for the relay — so that it does not take
443 from a web server or 1194 from a VPN you may run, and does not answer on the ports every
scanner tries first. That is why the address has a port in it. The ports stay the same for
the life of the server; the installer prints them at the end, and `dudescord status` names
them any time.

If your provider has a firewall or "security groups" in its control panel, these must be let
in. (`ufw` and `firewalld` on the machine itself are opened by the installer.)

| Port | For |
|---|---|
| TCP 80 | Let's Encrypt checks the address here when it issues or renews the certificate — nothing listens there the rest of the time, and no other port can do this |
| TCP, the site's port | the site and the connection of every client |
| TCP and UDP, the relay's port | the relay for people whose network blocks direct media |
| UDP 40000–49999 | voice and video |

Want the address without a port? Add `--port 443` to the install command (or set `PORT=443`
in the settings later). That moves the site only: a call still needs the relay's port and UDP
40000–49999, so from a network that lets nothing but 443 out people can open the site and
write, not talk.

### With a domain name

Point an `A` record at the machine, wait until it resolves, then:

```sh
curl -fsSL https://github.com/tapyard/dudescord/releases/latest/download/install.sh | sudo bash -s -- --address chat.example.org
```

### When port 80 is taken

The installer skips a port that something holds, so the site's and the relay's ports never
collide. Port 80 is the one it cannot move:

- Port 80 is busy with your own web server: keep it, make it forward
  `/.well-known/acme-challenge/` to `127.0.0.1:8089`, and add `--acme-port 8089`. For nginx:

  ```nginx
  location ^~ /.well-known/acme-challenge/ {
      proxy_pass http://127.0.0.1:8089;
      proxy_set_header Host $host;
  }
  ```

Options are remembered: later runs and updates need none of them.

### Settings

The settings are one file, `/opt/dudescord/dudescord.conf` — the address, the three ports and
an optional e-mail, each with a comment. To change one, edit the file and run
`sudo dudescord apply`: it checks the new values, then restarts the server. To see the
ground before installing, add `--check` to the install command: it runs every check and
changes nothing.

## Running it

Everything is one command on the server, as root:

```sh
dudescord invite                  # a new invite link, valid 7 days
dudescord invite --days 30
dudescord invites                 # the live links
dudescord revoke <link>           # the link stops working; accounts made with it stay
dudescord users                   # who has an account
dudescord owner <name>            # makes an account the owner: invites and accounts in the app's settings
dudescord owner <name> --remove   # …and takes that away
dudescord reset-password <name>   # prints a new password for someone who forgot theirs
dudescord remove <name>           # removes an account
dudescord remove <name> --restart # …and drops everyone connected right now
dudescord status                  # address, version, certificate, who is connected
dudescord config                  # the settings file and what is in it
dudescord apply                   # applies the settings file after an edit
dudescord update                  # the newest release; accounts and settings stay
dudescord uninstall               # removes everything (asks first)
```

An update or `apply` restarts the server: everyone drops for a few seconds and reconnects by
themselves. The commands that answer a question — everything above except `apply`, `update`
and `uninstall` — take `--json` for scripts and agents.

**The owner** sees a "Server" section in the app's settings (the gear): new invite links, the
list of accounts, a new password for someone who forgot theirs, removing an account. There
can be several owners.

**The address changed** (a new IP, or you got a domain): set `ADDRESS` in the settings file
and `dudescord apply` (or `dudescord update --address <new>`).
Accounts stay; people open the new address and log in with the same name and password. Old
invite links point at the old address — make a new one.

**Backup**: `/opt/dudescord/server.json`, `/opt/dudescord/dudescord.conf`, `/opt/dudescord/data/`
and `/opt/dudescord/groups/` are all there is — settings, accounts, invites, the certificate. The accounts are one file,
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
- **People join but do not hear each other** — UDP 40000–49999 or the relay's port (TCP and
  UDP; `turnPort` in `dudescord status --json`) is blocked by the provider's firewall.
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

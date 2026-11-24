# What is in this bundle

Dudescord — voice, video, screen sharing and chat for a group of friends on
their own server. MIT licence: `LICENSES/dudescord.txt`.

It contains and builds on:

- **Galene** (`galene`, parts of `static/`) — the videoconferencing server, by
  Juliusz Chroboczek and contributors. MIT licence: `LICENSES/galene.txt`.
  https://galene.org
- **Pion** WebRTC, ICE, TURN and related Go libraries, linked into `galene`.
  MIT licence. https://github.com/pion
- **lego** — the ACME client linked into `dudescordctl`. MIT licence.
  https://github.com/go-acme/lego
- **MediaPipe Tasks Vision** and its models (`static/third-party/tasks-vision/`)
  — background blur and face position, run in the browser. Apache License 2.0.
  https://github.com/google-ai-edge/mediapipe
- **Font Awesome Free**, **Toastify** and **contextual.js**
  (`static/third-party/`), shipped with Galene; their licences are beside the
  files.
- The Go standard library and `golang.org/x` packages. BSD 3-Clause licence.
  https://go.dev/LICENSE

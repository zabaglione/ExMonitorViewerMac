# ExMonitorViewerMac

- This is the independent macOS application, not the Windows ExMonitorViewer repository.
- Target macOS 26+, arm64; validation baseline is macOS 26.6.2; use Apple frameworks without third-party dependencies.
- Keep UI and runtime logs in English. Japanese documentation and comments are welcome.
- Never log captured content, window titles, or meeting details. Never write captured frames to disk.
- Keep capture, GPU rendering, window UI, and persistence separate. Retain at most the latest pending frame.
- Exclude this app from capture. Do not add input forwarding, Webex-specific hooks, private APIs, or virtual displays without a new request.
- Use `./scripts/build.sh` and `./scripts/test.sh`. Keep `build/`, `dist/`, and local visual evidence untracked.
- Report build, unit-test, GUI, actual frame-capture, external-display, and older-OS evidence separately.
- Before GitHub-bound commits, check scoped files and secrets and use the verified GitHub noreply identity.

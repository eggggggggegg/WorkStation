# WorkStation

WARNING THIS WAS MADE BY AI SO IF YOU DO NOT LIKE THAT KEWL BUT UH YKNOW LEAVE OR SUM IF U DONT WNANA LOSE IT

A browser-accessible workstation designed around a clean, reproducible filesystem, GPU acceleration, Selkies, dwm, and a Cloudflare Quick Tunnel.

## Goals

- Run a fast Linux workstation in the browser.
- Keep the host/runtime configuration separate from user data.
- Prefer GPU acceleration when the host provides a GPU, with software fallback where possible.
- Support multiple OS definitions over time rather than hard-coding one image.
- Eventually support full VM-backed Windows, Linux, macOS, and custom ISO sessions where the host and licensing allow it.
- Persist each OS version's user files in GitHub so the same OS can restore them on a later load.

## Repository layout

```
Pc/
  Os/
    <Osname>/
      Files/          # durable user files for this OS/version
      os.yaml         # OS definition and runtime metadata
config/               # workstation-wide configuration
runtime/              # persistence/runtime helpers
scripts/              # operator scripts
docs/                 # architecture and deployment notes
```

### Persistence

Every OS/version gets its own directory:

```
Pc/Os/<Osname>/Files/
```

The runtime must:

1. Load the selected OS definition.
2. Restore `Pc/Os/<Osname>/Files/` into the session's persistent home/data location.
3. Run the OS session.
4. Save changed user files back into that same directory when the session is stopped or explicitly saved.
5. Never mix files between OS versions.

Git is the durable transport for the repository-backed implementation. Runtime-generated caches, package downloads, logs, sockets, VM disks, and temporary files stay outside `Pc/Os/<Osname>/Files/` unless deliberately saved by the user.

> GitHub credentials must never be stored in the repository. The runtime should receive a short-lived or least-privilege token through the deployment environment.

## First target

The initial target is a Linux browser workstation using Selkies. The current Selkies project provides a desktop container and supports GPU-accelerated sessions; dwm can be introduced as the window manager/session layer as the image is customized. Selkies currently documents WebSocket streaming by default with WebRTC as an option.

Full VM support is a separate layer: QEMU/KVM/libvirt and OS-specific images should not be mixed into the basic Linux container.

## Development

The repository is intentionally small. Add functionality in layers:

1. workstation runtime
2. Linux desktop image
3. persistence
4. browser/tunnel entrypoint
5. VM manager
6. additional OS definitions

Do not commit build caches, VM disks, secrets, credentials, or generated runtime state.

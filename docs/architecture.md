# WorkStation architecture

## 1. Layers

### Host

The physical/cloud machine supplies:

- CPU
- RAM
- GPU
- storage
- Docker/Podman or an equivalent container runtime
- optional KVM acceleration for virtual machines

The host is never treated as the user's persistent filesystem.

### Session

A session is one selected OS definition, for example:

`Ubuntu-24.04`, `Windows-11`, or a future custom ISO.

A session has:

- an OS/runtime definition
- a private writable runtime directory
- a persistent user-data directory
- a browser streaming endpoint

### Persistence

Persistent files are namespaced by OS:

```
Pc/Os/<Osname>/Files/
```

This prevents a Linux session from accidentally restoring files belonging to another OS.

The persistence flow is:

```
GitHub repo
    |
    v
Pc/Os/<Osname>/Files/
    |
    v
session persistent-data directory
    |
    v
Selkies / VM
    |
    +---- user edits files
    |
    v
session persistent-data directory
    |
    v
Pc/Os/<Osname>/Files/
    |
    v
GitHub commit
```

Only the final user-data tree belongs in Git. Large runtime artifacts should use external storage later.

## 2. Clean filesystem rules

Tracked:

- source code
- OS definitions
- small configuration
- scripts
- user files explicitly selected for persistence

Not tracked:

- container layers
- package caches
- browser caches
- logs
- sockets
- temporary files
- VM disks
- swap/page files
- secrets
- GitHub tokens
- generated build directories

Use a separate runtime root such as `/var/lib/workstation` on the host.

## 3. Linux desktop

The first implementation should use Selkies for browser transport and a minimal Linux desktop image. The desktop session should be customized to use dwm rather than putting desktop configuration into the persistence tree.

GPU selection belongs to deployment configuration. Do not bake host-specific GPU paths into OS definitions.

## 4. Virtual machines

VM support is intentionally separate from the first containerized Linux session.

A future VM layer can expose:

- QEMU/KVM
- virtual disks
- ISO definitions
- snapshots
- per-OS storage

VM disks should live outside GitHub. Git is suitable for documents and configuration, not multi-gigabyte VM images.

## 5. Browser access

The browser-facing service is Selkies. A Cloudflare Quick Tunnel can be attached as an optional edge layer.

The tunnel should point at the local workstation service only. It must not become part of the OS filesystem or persistence mechanism.

## 6. GitHub persistence semantics

The persistence implementation should eventually provide:

- `load(os_name)`
- `save(os_name)`
- `status(os_name)`
- `diff(os_name)`

Saving should be atomic from the workstation's perspective:

1. stage only the selected `Pc/Os/<Osname>/Files/` tree
2. reject secrets and known runtime artifacts
3. commit with a descriptive message
4. push to the configured branch
5. record the resulting commit

Concurrent sessions for the same OS should be rejected or coordinated with a lock. Two sessions must not silently overwrite each other's files.

## 7. Security

GitHub credentials are deployment secrets. They must be injected at runtime and never copied into `Pc/Os/<Osname>/Files/`.

The first version should use a dedicated persistence token with the smallest practical repository permissions. Later, a backend can move GitHub operations away from the desktop host entirely.

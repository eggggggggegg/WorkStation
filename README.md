# WorkStation

WARNING: THIS WAS MADE WITH AI ASSISTANCE. Review the code before using it.

Do not commit build caches, VM disks, secrets, credentials, or generated runtime state.

## What this provides

WorkStation is a GitHub Actions-hosted Linux Mint desktop intended to be opened from a normal web browser.

The current bootstrap provides:

- Linux Mint 22 container environment
- DWM as the window manager
- Selkies 2.0 for browser-based desktop streaming
- Firefox and XTerm inside the desktop
- Cloudflare Quick Tunnel for a temporary HTTPS URL
- Persistent user home data under `persistent-data/home/`
- GitHub Actions as the ephemeral compute backend

Selkies 2.0 uses its default WebSocket transport here, so this setup does not require a separate TURN service. The public Cloudflare endpoint terminates HTTPS while forwarding to the local Selkies HTTP service.

## Start it

1. Open the repository's **Actions** tab.
2. Select **WorkStation**.
3. Choose **Run workflow**.
4. Leave the password blank to generate a random password, or provide one.
5. Wait for the **Start Cloudflare Quick Tunnel** step.
6. Open the `trycloudflare.com` URL shown in the workflow summary.
7. Log in with username `workstation` and the password shown in the same summary.

Quick Tunnel URLs are temporary and change between runs. They stop working when the workflow ends.

## Persistence

Files in the workstation home are copied into:

```
persistent-data/home/
```

at the end of a run and restored at the beginning of the next run.

Do not put secrets, credentials, browser profiles containing sensitive information, or large application caches in persistent storage. Git is not intended to be a general-purpose disk.

## Important GitHub Actions limits

This is an ephemeral workstation, not a permanent server. The workflow is intentionally bounded by the GitHub Actions job timeout. When the job ends, the desktop and Quick Tunnel disappear.

The repository's Actions token needs `contents: write` so the final persistence step can commit changes back to `persistent-data/`.

## Architecture

```
Browser
   |
   | HTTPS
   v
Cloudflare Quick Tunnel
   |
   | HTTP
   v
GitHub Actions runner
   |
   v
Docker / Linux Mint 22
   |
   +-- Xvfb
   +-- DWM
   +-- Firefox
   +-- Selkies 2
   |
   +-- /home/workstation -> persistent-data/home/
```

Quick Tunnels are a Cloudflare development/testing feature. They do not provide a stable hostname or production uptime guarantee.

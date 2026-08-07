# Deployment

There are two paths to production and they both land in the same directory on the NAS.

| | Push to `main` (CI) | `npm run deploy` (local) |
| --- | --- | --- |
| Runs | GitHub Actions, `ubuntu-latest` | Your Mac |
| Trigger | every push to `main`, or manual dispatch | you, deliberately |
| What ships | a fresh build of the committed tree | a fresh build of your working tree |
| Uncommitted work | never ships | ships |
| Auth | `SSH_PRIVATE_KEY` repo secret | ssh-agent, or `SSH_KEY_PATH` in `.env` |
| Safety gates | `--max-delete=50`, payload sanity check | dirty-tree check, on-`main` check, typed confirmation, `--max-delete=50` |
| Dry run | dispatch with `dry_run` checked | `./utils/deploy/prod.sh --dry-run` |

CI is the default. The local script exists for when you want to watch it happen, or ship something you haven't committed.

## The single source of truth

Neither path hardcodes the target. Both read it from the same files, so they cannot drift apart.

| Fact | Lives in | Read by |
| --- | --- | --- |
| host / username / port / remotePath | `.vscode/sftp.json` | VS Code SFTP extension, `deploy.sh`, the workflow |
| rsync excludes | `utils/deploy/ignore.json` → `patterns[]` | `deploy.sh`, the workflow |
| CI-only protections | `utils/deploy/ignore.json` → `protect[]` | the workflow only |
| credentials | `.env` locally, repo secrets in CI | each path separately |

`.vscode/sftp.json` is deliberately git-tracked even though the rest of `.vscode/` is ignored. CI reads the deploy target out of the checkout. It holds no credentials, so tracking it is safe.

**If the remote path changes, change it in `sftp.json` and nowhere else.**

## What ships

Unlike onlyziads.com, this project rsyncs **the build output**, not the repo root. Both paths run `npm run build` and then sync `_site/` into the web root. Eleventy decides what ships; `ignore.json` only catches stray junk like `.DS_Store`.

That has one consequence worth internalizing: **anything on the server that the build does not produce will be deleted.** If you ever hand-place a file in the web root (a domain verification file, a big asset), add its pattern to `protect[]` in `ignore.json` **first**, or the next deploy removes it. Nothing warns you.

<!--| PAGE-BREAK -->

## How the NAS actually serves things

Worth knowing before you change anything, because there are two separate patterns already running on it.

| Pattern | Used by | Mechanism |
| --- | --- | --- |
| Static sites | `feralcreative.dev`, `move.ezzat.com`, `moveawayfromtheblacks.com`, `securesite.dev` | Web Station virtual host, **Nginx** backend, doc root under `/volume1/web/<domain>` |
| App sites | `fuckpicrights.com`, `househunt.ezzat.com`, `ziad.af`, `routeloop.app`, ~14 more | Docker container on a local port, plus a DSM **Reverse Proxy** rule pointing the hostname at it |

omgstop.org is the first pattern: a Web Station virtual host over `/volume1/web/omgstop.org`.

Traffic gets in through **Cloudflare Tunnel**, not a forwarded HTTP port. `cloudflared` runs on the NAS with a token-based config, which means the ingress rules (public hostname → local service) live in the Cloudflare Zero Trust dashboard, not in any file on the NAS. Adding a site therefore takes **two** steps, not one: the Web Station virtual host, and a public hostname on the tunnel.

## One-time setup

### 1. Register the domain

`omgstop.org` **is not registered.** WHOIS returns "Domain not found" and RDAP returns 404, so there is no DNS to configure and no Cloudflare zone to add a record to. Everything below is blocked on this.

### 2. Web root (done)

`/volume1/web/omgstop.org` exists, is `755 ziad:users`, and currently holds a build of the site with `644` files. Nothing to do unless you want it somewhere else, in which case change `remotePath` in `.vscode/sftp.json` and nowhere else.

### 3. Create the Web Station virtual host

This is a DSM operation and cannot be scripted over SSH—the configs in `/usr/local/etc/nginx/sites-enabled/` are generated from DSM's own database and get overwritten, and `ziad` has no passwordless sudo.

In **Web Station → Web Service**, create a static website with `/volume1/web/omgstop.org` as its document root, then in **Web Portal** bind it to the hostname `omgstop.org`.

**Backend server: Nginx**, matching your other static sites. The behavior an `.htaccess` would have given on Apache comes from `utils/deploy/nginx-user.conf` instead, installed in the next step. No Apache config ships with this project.

### 4. Install the Nginx vhost config

```bash
./utils/deploy/install-nginx-conf.sh
```

It finds the vhost by its document root, drops `nginx-user.conf` into the `user.conf` hook Web Station already includes, validates with `nginx -t`, and reloads. The conf tree is root-owned, so it opens an interactive SSH session and asks for your DSM password once. `--dry-run` locates the vhost and changes nothing.

Without this the site still works, but you get DSM's default 404 page, no security or cache headers, and a 301 hop on `/less`.

### 5. Add the tunnel hostname

In the Cloudflare Zero Trust dashboard, under the tunnel serving this NAS, add a public hostname for `omgstop.org` pointing at `http://localhost:80`. Cloudflare creates the DNS record itself, so there is no separate A/CNAME step.

### 6. Create a dedicated deploy key

Never put your personal key in a GitHub secret. A separate keypair can be revoked on its own.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/omgstop_deploy -C "github-actions@omgstop.org" -N ""
```

```bash
ssh-copy-id -i ~/.ssh/omgstop_deploy.pub -p 33725 ziad@nas.feralcreative.co
```

Synology is fussy about SSH key auth. If `ssh-copy-id` succeeds but key auth still doesn't work, check on the NAS that `/volume1/homes/ziad` is `755`, `~/.ssh` is `700`, and `~/.ssh/authorized_keys` is `600`, and that **User Home Service** is enabled in Control Panel. Group-writable home directories make sshd silently refuse the key.

### 7. Set the repository secrets

Each command pipes its value in on stdin, so no secret reaches your shell history. Run them one at a time.

```bash
gh secret set SSH_PRIVATE_KEY < ~/.ssh/omgstop_deploy
```

```bash
ssh-keyscan -p 33725 -H nas.feralcreative.co | gh secret set SSH_KNOWN_HOSTS
```

```bash
grep -E '^CLOUDFLARE_API_TOKEN=' .env | cut -d= -f2- | tr -d '"' | gh secret set CLOUDFLARE_API_TOKEN
```

```bash
grep -E '^CLOUDFLARE_ZONE_ID=' .env | cut -d= -f2- | tr -d '"' | gh secret set CLOUDFLARE_ZONE_ID
```

| Secret | Required | Effect if missing |
| --- | --- | --- |
| `SSH_PRIVATE_KEY` | yes | deploy fails immediately |
| `SSH_KNOWN_HOSTS` | recommended | falls back to trust-on-first-use, with a warning |
| `CLOUDFLARE_API_TOKEN` | no | cache purge skipped, deploy still succeeds |
| `CLOUDFLARE_ZONE_ID` | no | cache purge skipped, deploy still succeeds |

### 8. Dry-run before trusting it

From the Actions tab, run the workflow manually with `dry_run` checked. Read the file list. Confirm the deletions are all things you meant to delete. Only then push for real.

<!--| PAGE-BREAK -->

## The reachability assumption

CI reaches the NAS by SSHing straight to `nas.feralcreative.co:33725` from a GitHub-hosted runner. That requires port 33725 to be forwarded and reachable from the public internet—not just from your LAN.

**This is still unverified, and there is now reason to doubt it.** SSH to that host and port works from your Mac, but your Mac is at `192.168.1.75` and the NAS is at `192.168.1.3`—same subnet, so that connection proves only that NAT hairpin works, not that anything outside can get in. The stronger signal is that HTTP ingress runs entirely over Cloudflare Tunnel, which is what people use specifically so they don't have to forward ports.

If the `Configure SSH` step fails with an empty `known_hosts`, that is what happened, and there are three ways out:

1. Forward the port (simplest, and it is already how the local script works).
2. Put a self-hosted GitHub runner on the NAS, so nothing inbound is needed. The workflow becomes `runs-on: self-hosted` and the rsync becomes a local copy.
3. Route CI through a Cloudflare Tunnel with an Access service token.

Given the tunnel is already there, option 2 is probably the better fit for this NAS: a self-hosted runner needs nothing inbound at all, and the deploy becomes a local file copy. Option 1 is still the least work if the port already happens to be open.

## The Nginx config

`utils/deploy/nginx-user.conf` is the whole of it. Web Station's generated server block ends with `include /usr/local/etc/nginx/conf.d/<service-uuid>/user.conf*;`—a glob, so the file is optional and the vhost works without it. `install-nginx-conf.sh` fills that slot.

Two things in it are load-bearing and non-obvious, both found by testing rather than reasoning.

### `try_files $uri $uri/index.html $uri/ =404;`

The idiomatic `try_files $uri $uri/ =404;` **does not** serve `/less` directly. The `$uri/` test matches the directory, and Nginx answers with a **301 to `/less/`**—a wasted round trip on the exact URL the entire site exists to be typed into. Naming `index.html` explicitly, ahead of the directory test, serves it in place:

| Request | `$uri $uri/ =404` | `$uri $uri/index.html $uri/ =404` |
| --- | --- | --- |
| `/less` | 301 → `/less/` | **200** |
| `/less/` | 200 | 200 |
| `/` | 200 | 200 |
| `/nope` | 404 | 404 |

### `expires -1;` at server level, not in a `location`

HTML reached through the clean-URL rule is served from inside `location /`, so a `location ~* \.html$` block never matches it and the pages would silently inherit whatever the asset cache rule said. Setting the no-cache default at server level and opting assets back in with `expires` is the only arrangement that holds.

That also explains why the asset blocks use **only** `expires` and never `add_header`: a `location` that declares its own `add_header` discards every inherited one, which would quietly strip the three security headers from CSS and SVG. Verified—assets come back with `Cache-Control: max-age=604800` *and* all three headers intact.

### How this was verified

Rather than reload it into the live Nginx and find out, the config was tested in a throwaway `nginx:alpine` container on the NAS, bound to `127.0.0.1:18099`, with the real `/volume1/web/omgstop.org` mounted read-only and a server block mimicking Web Station's. Every row of the table above, plus the header behavior, came from that. The container and its staging directory were removed; the `nginx:alpine` image (62 MB) is still cached if you want to repeat it.

## URLs

Every entry builds to a directory with an `index.html`, so `omgstop.org/less` and `omgstop.org/less/` both work. With the Nginx config installed, both are a direct 200. Without it, the no-slash form takes a 301 first—correct either way, just one extra hop.

<!--| PAGE-BREAK -->

## The rsync flags that matter

These are inherited from the onlyziads.com deploy, where each one was added in response to something that actually broke. Don't drop them to simplify.

### `--checksum` (CI only)

rsync's default compares size and mtime. Every CI build writes fresh mtimes, so the default marks every file as changed and re-uploads the whole site on every push. `--checksum` compares content hashes instead. The local script omits it because a local build's mtimes are stable enough.

### `--chmod=D755,F644`

`rsync -a` preserves source permissions, which is wrong for a web server. Web Station runs as a different user, so a mode-700 directory or mode-600 file becomes a 403 no matter how correct its contents are. Directories are the worse case: one non-traversable directory 403s everything inside it.

Both paths set it, and both follow up with a server-side `find`/`chmod` pass that catches anything rsync couldn't touch. macOS now ships openrsync, which has no `--chmod`, so `deploy.sh` feature-detects it and leans on the post-sync pass when it's missing.

### `--max-delete=50`

A deploy that wants to remove 50+ files is a broken build, not a cleanup. rsync exits 25 and removes nothing beyond the cap. Re-run via workflow dispatch with a higher `max_delete` if a large removal is genuinely intended.

### `--delete-after`

Deletions run after the transfer, so a mid-transfer failure leaves the old site in place rather than a half-deleted one.

### `concurrency: cancel-in-progress: false`

Two rsyncs into one directory corrupt each other. Queueing is better than cancelling, because a killed rsync leaves the server in a state that matches no commit.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `known_hosts is empty` in CI | The NAS didn't answer on port 33725 from the runner. See the reachability section above |
| `Permission denied (publickey)` | The deploy key's public half isn't in `authorized_keys`, or home/`.ssh` permissions on the NAS are too loose. See setup step 3 |
| `Host key verification failed` | `SSH_KNOWN_HOSTS` is stale. Re-run the `ssh-keyscan` command and update the secret |
| rsync exits 25 | `--max-delete` fired. Nothing beyond the cap was removed. Read what it wanted to delete before raising the limit |
| Scattered 403s on files that exist | Permissions. The normalize step should have caught it—check that it ran and what it reported |
| `/less` 301s instead of 200 | The Nginx `user.conf` is not installed. Run `./utils/deploy/install-nginx-conf.sh` |
| Site loads unstyled | The build step failed, or `*.css` ended up in `patterns[]` in `ignore.json` |
| A file never deploys | Check it against **both** arrays in `ignore.json`. `protect[]` blocks uploads as well as deletions |
| Stale content after a deploy | Cloudflare purge was skipped because its two secrets aren't set. Check the workflow log for the warning |

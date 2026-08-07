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

## One-time setup

Five things, in order. Nothing works until all five are done.

### 1. Point the domain at the NAS

`omgstop.org` currently resolves to nothing. Add the DNS record (Cloudflare, presumably, to match onlyziads.com) pointing at the NAS. If you proxy it through Cloudflare, the origin still needs a real certificate or a Cloudflare Tunnel—Web Station's self-signed cert will fail a Full (strict) origin check.

### 2. Create the web root and the virtual host in DSM

The deploy target is `/volume1/web/omgstop.org`. Create it, then add a Web Station virtual host bound to `omgstop.org` with that as its document root.

```bash
ssh -p 33725 ziad@nas.feralcreative.co "mkdir -p /volume1/web/omgstop.org"
```

**Pick Apache, not Nginx, in the virtual host settings**—or read the Nginx note below before you pick Nginx. `src/static/.htaccess` handles clean URLs, the 404 page, caching, and security headers, and it is read only by Apache.

### 3. Create a dedicated deploy key

Never put your personal key in a GitHub secret. A separate keypair can be revoked on its own.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/omgstop_deploy -C "github-actions@omgstop.org" -N ""
```

```bash
ssh-copy-id -i ~/.ssh/omgstop_deploy.pub -p 33725 ziad@nas.feralcreative.co
```

Synology is fussy about SSH key auth. If `ssh-copy-id` succeeds but key auth still doesn't work, check on the NAS that `/volume1/homes/ziad` is `755`, `~/.ssh` is `700`, and `~/.ssh/authorized_keys` is `600`, and that **User Home Service** is enabled in Control Panel. Group-writable home directories make sshd silently refuse the key.

### 4. Set the repository secrets

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

### 5. Dry-run before trusting it

From the Actions tab, run the workflow manually with `dry_run` checked. Read the file list. Confirm the deletions are all things you meant to delete. Only then push for real.

<!--| PAGE-BREAK -->

## The reachability assumption

CI reaches the NAS by SSHing straight to `nas.feralcreative.co:33725` from a GitHub-hosted runner. That requires port 33725 to be forwarded and reachable from the public internet—not just from your LAN or over Tailscale.

`nas.feralcreative.co` resolves through `feralcreative.synology.me` to a public IP, so the DNS half is fine. Whether the port answers from outside has not been tested from here. If the `Configure SSH` step fails with an empty `known_hosts`, that is what happened, and there are three ways out:

1. Forward the port (simplest, and it is already how the local script works).
2. Put a self-hosted GitHub runner on the NAS, so nothing inbound is needed. The workflow becomes `runs-on: self-hosted` and the rsync becomes a local copy.
3. Route CI through a Cloudflare Tunnel with an Access service token.

Option 1 unless you'd rather not open the port.

## Apache vs Nginx on Web Station

`src/static/.htaccess` is read **only** by Apache. If the virtual host is set to Nginx, DSM ignores the file completely and you silently lose clean URLs, the custom 404, cache headers, and the security headers. The site still works; it just quietly stops doing four things.

If you'd rather run Nginx, the equivalent goes in the virtual host's Nginx config:

```nginx
index index.html;
error_page 404 /404.html;

location / {
  try_files $uri $uri/ $uri.html =404;
}

add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

location ~* \.html$ {
  expires -1;
}

location ~* \.(css|svg)$ {
  expires 7d;
}
```

## URLs

Every entry builds to a directory with an `index.html`, so `omgstop.org/less` and `omgstop.org/less/` both work. Without the `.htaccess` rewrite, the no-slash form takes a 301 redirect first—correct either way, just one extra hop.

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
| `/less` 404s but `/less/` works | The virtual host is on Nginx, so `.htaccess` is being ignored. See the Nginx config above |
| Site loads unstyled | The build step failed, or `*.css` ended up in `patterns[]` in `ignore.json` |
| A file never deploys | Check it against **both** arrays in `ignore.json`. `protect[]` blocks uploads as well as deletions |
| Stale content after a deploy | Cloudflare purge was skipped because its two secrets aren't set. Check the workflow log for the warning |

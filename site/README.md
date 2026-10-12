# voceapp.link

The landing page for Voce, served by Cloudflare Workers static assets at https://voceapp.link.

- `public/` is the site. It is plain HTML and CSS with no build step.
- `wrangler.jsonc` binds the Worker to the `voceapp.link` and `www.voceapp.link` custom domains.
- `.github/workflows/site.yml` deploys on every push to `main` that touches this directory.

## Deploy

From CI, set the repository secrets `CLOUDFLARE_API_TOKEN` (Workers Scripts: Edit, Workers Routes: Edit, Zone DNS: Edit on voceapp.link) and `CLOUDFLARE_ACCOUNT_ID`.

By hand:

```bash
cd site
npm install
npx wrangler login     # or export CLOUDFLARE_API_TOKEN=...
npm run deploy
```

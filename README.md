# Heart Adoption

Native SwiftUI app for helping shelter and street dogs and cats find homes, with a TypeScript API and Neon Postgres database. Requires iOS 17+, Xcode 15+, and Node 22+ (Node 24 is used in the container and CI).

## Run the app

Open `HeartAdoption.xcodeproj`, choose the **HeartAdoption** scheme and an iPhone Simulator, and run. No third-party Swift packages are needed.

The app connects to the deployed Neon Function by default. **You → Explore the app preview** opens a labelled sample world with bundled photos. Preview posts, likes, and country follows persist locally. **You → Sample account** switches between Alex (regular user) and Sofia (administrator for Italy and Greece). These accounts never grant permissions on a connected server.

## Run with Neon

```sh
cd server
npm ci
cp .env.example .env
# Set DATABASE_URL to your Neon connection string in .env.
npm run dev -- --local
```

The API applies the versioned schema and seeds all 249 ISO country groups on startup. `--local` binds to localhost and uses local photo/share URLs, while still reading `DATABASE_URL` from `.env`. Without a `DATABASE_URL`, development uses a persistent embedded Postgres database in `server/.data/local`.

In the app, choose **You → Connect to a server**, enter `http://localhost:8787`, and create an account. This localhost address works in the iOS Simulator. A physical iPhone needs an HTTPS API address.

Alternatively, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `API_BASE_URL` before building. `.env` and `Local.xcconfig` are ignored by Git. Database credentials belong only on the server; iOS stores its opaque session token in Keychain.

## What works

- Register, sign in, edit a profile/home country, sign out, and delete an account.
- Publish a dog or cat with 1–6 photos, age, sex, size, care information, story, city, country, and contact email. Uploaded photos are resized and their metadata is removed.
- Browse the home country, followed countries, all countries, or a specific country group. Search names, cities, and stories across borders; filter dogs and cats.
- Like/unlike posts and keep a personal liked feed. Follow/unfollow country groups.
- Open an animal's detail page and email its carer. Owners can edit posts, mark animals adopted, or delete posts.
- Share posts using the iOS share sheet. `/p/:id` provides a public page with a photo and social preview metadata, plus a link back into the app.
- Invite friends with the native share sheet and an `/invite` landing page. Configure `APP_STORE_URL` once a listing is available; before that, the page directs people to request a TestFlight invitation.
- Report posts. Country administrators can review reports, hide/restore posts, and administer multiple assigned countries. Hidden posts and their photos are removed from public APIs and share pages.

Posts publish immediately in their animal's country group. The home country affects the default feed, not who can discover a post. Adopted animals leave discovery but stay in their owner's posts.

## Assign administrators

After the person registers:

```sh
cd server
npm run admin -- person@example.org IT GR
```

Assignments are stored in `country_admins` and enforced by the API, not by an editable profile field. To revoke a country assignment, delete that user's corresponding row from `country_admins` in the Neon SQL editor. Regular users cannot assign roles. Moderation changes have an audit record in `moderation_events`.

## Verify

```sh
cd server
npm run build
npm test
# Optional live check against the DATABASE_URL in .env:
npm run dev -- --verify-neon --local
```

The API suite runs actual Postgres queries in PGlite and covers authentication, input validation, photo processing, country feeds, cross-country follows/search, pagination, likes, public sharing, role escalation attempts, moderation boundaries, adoption status, and account deletion. The live Neon check creates temporary accounts and a photo post, checks the shared flows through the API handlers, then deletes its records.

```sh
xcodebuild -project HeartAdoption.xcodeproj -scheme HeartAdoption \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO test
```

Choose a simulator name installed on your Mac. Keep the default simulator signing enabled so Keychain can store sessions. Native tests check persistence and country permissions; UI tests cover discovery, cross-country search, follows, likes, posting, sharing, and moderation. The live-client native test runs when a local API is available and skips otherwise.

`python3 scripts/generate-project.py` regenerates the checked-in Xcode project after adding Swift files. `node scripts/generate-countries.mjs` regenerates the country catalog. `swift scripts/create-assets.swift` regenerates the original vector-drawn app icon.

## Deploy the API

The production API runs on [Neon Functions](https://neon.com/docs/compute/functions/overview) in the same Frankfurt region as Postgres:

`https://br-restless-sun-b94jjzho-heartadoption.compute.c-7.eu-central-1.aws.neon.tech`

`server/src/neon-function.ts` exports Neon's Fetch handler and reuses the same API routes and authorization. The function keeps a small Postgres pool per isolate. Basic request throttles are per isolate; they are not an edge firewall or a shared cross-isolate quota.

Build a deployment archive from any supported development machine:

```sh
cd server
npm run build:function
```

The builder bundles JavaScript, downloads the Linux ARM64/glibc Sharp prebuilds pinned in the lockfile, verifies their SHA-512 checksums, and writes `build/heart-adoption-function.zip`. Development PGlite and database credentials are excluded from the archive. Neon runs `index.mjs` on Node 24. The platform's `PUBLIC_URL` must be set to the function's invocation origin, and `DATABASE_URL` must point to the migrated adoption database. Apply migrations before publishing a new function version.

For a deployment check against the real public endpoint (using temporary accounts cleaned up afterward):

```sh
cd server
npm run dev -- --verify-public
```

The Neon management API key and project/branch identifiers are read from the ignored `server/.env` for deployment administration. They never belong in the app or function archive. The native app contains only the public API origin.

### Alternative container host

The root `Dockerfile` builds the API. Deploy it to an HTTPS-capable container host with:

| Variable | Value |
| --- | --- |
| `DATABASE_URL` | Neon pooled connection string with `sslmode=verify-full` |
| `PUBLIC_URL` | Public HTTPS origin of this API, used for photo and share URLs |
| `PORT` | Host-provided port, or `8787` |
| `APP_STORE_URL` | Optional real App Store listing URL |

The container listens on `0.0.0.0` and uses `/health` for health checks. Production requires an external Postgres database and HTTPS `PUBLIC_URL`. Set the same public origin in the iOS app. Sharing links outside your development machine requires this public deployment. App Store/TestFlight distribution also requires your Apple developer signing team.

Photos are bounded, processed JPEGs stored in Postgres for this first version, so a deployment does not depend on a separate storage provider. Monitor database size; an object storage adapter is the natural next step as photo volume grows. Accounts currently use email/password without email delivery, verification, or password recovery. Followed countries are feed subscriptions; push notifications are not part of this version.

## Sample photo credits

Bundled sample photos come from [Unsplash](https://unsplash.com/license) and represent fictional adoption profiles: [Milo](https://images.unsplash.com/photo-1552053831-71594a27632d), [Luna](https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba), [Olive](https://images.unsplash.com/photo-1517849845537-4d257902454a), [Nori](https://images.unsplash.com/photo-1513360371669-4adf3dd7dff8), and [Teddy](https://images.unsplash.com/photo-1543466835-00a7907e9de1). The app icon is original code-drawn artwork.

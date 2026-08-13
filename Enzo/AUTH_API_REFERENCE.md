# Auth API Reference (Person B → Person C handoff)

**Base URL:** `https://diet-analysis-auth-func-2026.azurewebsites.net`

## You don't need to deploy or provision anything

This API is already live under my own Azure subscription. Just call it from the dashboard's JavaScript like any external API. CORS is already open (`Access-Control-Allow-Origin: *`), so requests work from any origin without extra config on your end.

---

## POST /api/register

**Body:**
```json
{ "email": "user@example.com", "password": "at least 8 chars", "name": "Jane Doe" }
```

**Success (201):**
```json
{ "token": "<JWT>", "name": "Jane Doe", "email": "user@example.com" }
```

**Errors:** `400` invalid email/password/name · `409` email already registered

---

## POST /api/login

**Body:**
```json
{ "email": "user@example.com", "password": "..." }
```

**Success (200):** same shape as register.

**Errors:** `401` invalid email or password

---

## POST /api/logout

No body needed. Returns `200 { "message": "Logged out" }`.

JWTs are stateless, so this doesn't invalidate anything server-side — the actual logout is on your end: delete the stored token and show the login screen again. Calling this endpoint first is just good practice, not strictly required.

---

## GET /api/me

**Header:** `Authorization: Bearer <token>`

**Success (200):**
```json
{ "email": "user@example.com", "name": "Jane Doe" }
```

Call this on dashboard load to confirm the stored token is still valid and to get the name for the top-right corner display.

**Errors:** `401` if the token is missing, invalid, or expired — treat this as "not logged in" and show the login screen.

---

## GET /api/auth/github/login

This one isn't a `fetch()` call — it's a link. Point your "Login with GitHub" button directly at it:

```html
<button onclick="window.location.href = 'https://diet-analysis-auth-func-2026.azurewebsites.net/api/auth/github/login'">
  Login with GitHub
</button>
```

It redirects the whole browser to GitHub, the user approves access, GitHub redirects back through my callback function, and that lands the browser back on:

```
YOUR_DASHBOARD_URL/#token=<JWT>
```

### What your JS needs to do on page load

```js
const hash = window.location.hash;
if (hash.startsWith('#token=')) {
  const token = hash.substring('#token='.length);
  localStorage.setItem('authToken', token);
  window.location.hash = ''; // clean up the URL bar
}
```

From there, use the stored token the same way for both login paths — attach it as `Authorization: Bearer <token>` on `/api/me` and any other calls that need to know who's logged in.

---

## One thing I need from you

Send me your dashboard's URL (local dev URL for now, real deployed URL once you have it) — I need to set that as my Function App's `FRONTEND_URL` setting so the GitHub redirect lands in the right place. It's currently pointed at a placeholder.

## Security notes

- You never need the Cosmos DB key, JWT secret, or GitHub client secret — all of that stays server-side on my Function App. You only ever talk to it over HTTPS.
- Treat the token as a credential: keep it in `localStorage` (or memory), don't put it in a shared URL, and clear it on logout.

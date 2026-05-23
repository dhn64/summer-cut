# Firestore 403 on all data endpoints (v1.3.1 and v1.4.6)

## Summary

All Firestore read/write operations return 403 "Missing or insufficient permissions" as of ~May 19, 2026. Auth succeeds (verified by logging into MacroFactor app with the same email/password credentials), but every data request is blocked.

Separately, v1.4.6 introduced a regression: `getFirebaseApiKey()` now reads from `FIREBASE_WEB_API_KEY` env var instead of a hardcoded key, but this isn't documented. The server crashes on startup with "Method doesn't allow unregistered callers" until you add the env var. (Workaround below.)

## Environment

- Package: `@sjawhar/macrofactor-mcp` (tested on both 1.3.1 and 1.4.6)
- Platform: Windows 11, Claude Desktop (MCP stdio transport)
- Node: v20.x
- Auth method: email/password (originally Google Sign-In, password added via MacroFactor account settings)

## v1.4.6 startup crash (fixed with workaround)

The server crashes immediately after connecting:

```
Fatal: Sign-in failed (403): {
  "error": {
    "code": 403,
    "message": "Method doesn't allow unregistered callers (callers without established identity). Please use API Key or other form of API consumer identity to call this API.",
    "status": "PERMISSION_DENIED"
  }
}
Assertion failed: !(handle->flags & UV_HANDLE_CLOSING), file src\win\async.c, line 76
```

**Root cause:** `getFirebaseApiKey()` at line 6870 of `chunk-GAHKBI2M.js` returns `_env.VITE_FIREBASE_WEB_API_KEY ?? process.env.FIREBASE_WEB_API_KEY ?? ""`, but this env var isn't documented and wasn't required in 1.3.1 (where the key was hardcoded).

**Workaround:** Add to config env block:
```json
"FIREBASE_WEB_API_KEY": "AIzaSyA17Uwy37irVEQSwz6PIyX3wnkHrDBeleA"
```
(Key extracted from v1.3.1 bundle.)

## Firestore 403 on all data access (both versions)

After auth succeeds, every Firestore operation returns 403:

```
Firestore GET users/<uid> failed (403): {
  "error": {
    "code": 403,
    "message": "Missing or insufficient permissions.",
    "status": "PERMISSION_DENIED"
  }
}
```

Affected endpoints (all tested):
- `get_profile` → `users/{uid}` → 403
- `get_food_log` → `users/{uid}/food/{date}` → 403
- `get_weight_entries` → `users/{uid}/scale/{year}` → 403
- `log_manual_food` → PATCH `users/{uid}/food/{date}` → 403
- `get_context` → 403

`get_nutrition` returns `[]` (no error), but this may not hit Firestore directly.

**Verified:** Logging into the MacroFactor app with the same email/password works fine -- all data is accessible. The account and credentials are valid.

**Timeline:** This started around May 19, 2026. The MCP was working normally before that date with v1.3.1.

## Likely cause

MacroFactor appears to have changed their Firestore security rules or enabled App Check enforcement on user data collections. The REST API path (`firestore.googleapis.com/v1/projects/sbs-diet-app/...`) is now blocked even with a valid Firebase auth token.

## Questions

1. Did MacroFactor recently tighten Firestore rules or enable App Check on data collections?
2. Should `FIREBASE_WEB_API_KEY` be documented as a required env var for v1.4.6, or was the key removal unintentional?

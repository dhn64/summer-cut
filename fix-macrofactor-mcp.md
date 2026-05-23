# Fix MacroFactor MCP -- Troubleshooting Guide

## Context
The MacroFactor MCP server (`@sjawhar/macrofactor-mcp` by sjawhar) is returning Firestore 403 on ALL endpoints -- reads and writes. Started around May 19, 2026.

## How it's set up
- **Package:** `@sjawhar/macrofactor-mcp` (installed globally via npm)
- **Config file:** `%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\claude_desktop_config.json`
- **Auth method:** Firebase email/password (Danny added a password to his Google Sign-In MacroFactor account specifically for this)
- **Credentials:** stored in Keeper

Config block looks like:
```json
"macrofactor": {
  "command": "npx",
  "args": ["@sjawhar/macrofactor-mcp"],
  "env": {
    "MACROFACTOR_USERNAME": "email@gmail.com",
    "MACROFACTOR_PASSWORD": "the_password"
  }
}
```

## Troubleshooting steps (in order)

### 1. Update the npm package
MacroFactor may have changed their Firebase/Firestore setup. sjawhar may have pushed a fix.
```powershell
npm update -g @sjawhar/macrofactor-mcp
```
Then restart Claude Desktop (fully quit and reopen -- the MCP server restarts with it).

### 2. Verify password still works
Log into MacroFactor's website or app with the email/password (not Google Sign-In). If the password doesn't work, reset it in MacroFactor account settings, update the password in Keeper, and update `claude_desktop_config.json`.

### 3. Check sjawhar's GitHub for issues
Look at https://github.com/sjawhar/macrofactor-mcp/issues for any reports of 403 errors or breaking changes from a MacroFactor app update.

### 4. Test after each change
Call any read endpoint:
```
macrofactor:get_nutrition with startDate=2026-05-22, endDate=2026-05-22
```
If it returns data instead of 403, we're back.

## Once it's working -- backfill these gaps

Pull these for the Summer Cut project (`summer-cut/data.json`):
- **May 19:** food log + nutrition (completely missing)
- **May 20:** food log + nutrition + weight (completely missing)
- **May 21:** weight only (nutrition was pulled before outage)
- **May 22:** food log (we have partial -- tuna roll + poke bowl manually logged, need full day)
- **May 23:** weight already logged manually (173 lbs), but sync to MF too

Log these to MacroFactor if writes work:
- M2M Tuna Roll (6pc): 290cal/18P/48C/2F at 5:00 PM on 2026-05-22
- Poke Bowl (rice reduced, 572g eaten): 900cal/64P/71C/41F at 7:00 PM on 2026-05-22

## Error details
```
Firestore GET users/QfDhK0mL0mMlnvSXQi3mR7RSbR03/food/2026-05-22 failed (403):
{
  "error": {
    "code": 403,
    "message": "Missing or insufficient permissions.",
    "status": "PERMISSION_DENIED"
  }
}
```
Same 403 on all endpoints: get_food_log, get_nutrition, get_weight_entries, log_manual_food.

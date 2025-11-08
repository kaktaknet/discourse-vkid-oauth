# Migration Guide: Upgrading to VK ID 2.0

This guide helps you migrate from the old VK OAuth plugin (v1.x) to the new VK ID plugin (v2.0).

## What Changed?

| Aspect | Old (v1.x) | New (v2.0) |
|--------|-----------|-----------|
| **Provider** | VK OAuth (oauth.vk.com) | VK ID (id.vk.ru) |
| **OAuth Version** | OAuth 2.0 | OAuth 2.1 with PKCE |
| **Provider Name** | `vkontakte` | `vkid` |
| **Settings Prefix** | `vk_*` | `vkid_*` |
| **Gem Dependency** | `omniauth-vkontakte` | Custom strategy (no gem) |
| **PKCE** | Not supported | Mandatory |

## Pre-Migration Checklist

- [ ] **Backup your database** before upgrading
- [ ] Note down your current VK App ID and Secure Key
- [ ] Check how many users use VK login: `UserAssociatedAccount.where(provider_name: 'vkontakte').count`
- [ ] Inform users about the upgrade (optional, seamless migration)

## Migration Steps

### Step 1: Update VK Application Settings

1. Go to https://id.vk.com/about/business/go
2. Open your VK application settings
3. Update the **Redirect URI**:
   ```
   https://your-discourse-site.com/auth/vkid/callback
   ```
   Note: `/vkid/` instead of old `/vkontakte/`

4. Ensure **PKCE is enabled** in OAuth settings
5. Verify scopes include: `vkid.personal_info`, `email`

### Step 2: Update Plugin

1. The plugin auto-updates if installed via git. If not, pull latest changes:
   ```bash
   cd /var/discourse
   ./launcher enter app
   cd plugins/discourse-vk-auth
   git pull
   exit
   ```

2. Rebuild Discourse:
   ```bash
   cd /var/discourse
   ./launcher rebuild app
   ```

### Step 3: Configure New Settings

1. Go to **Admin** → **Settings** → **Login**
2. Search for "VK ID"
3. Configure:

   | Setting | Value |
   |---------|-------|
   | `vkid_enabled` | ✅ Check this |
   | `vkid_client_id` | Your VK App ID |
   | `vkid_client_secret` | Your VK Secure Key |
   | `vkid_scope` | `vkid.personal_info email phone` |

4. **Disable old settings** (if still visible):
   - Uncheck `vk_auth_enabled`

### Step 4: Choose Migration Method

You have two options:

#### Option A: Automatic Migration (Recommended)

Users are **automatically migrated** when they log in:

1. User clicks "Login with VK ID"
2. Authenticates with VK
3. Plugin detects old `vkontakte` account
4. Updates to `vkid` automatically
5. User logged in seamlessly

**Pros**: No manual work, zero downtime
**Cons**: Users migrate gradually (as they log in)

#### Option B: Bulk Migration

Migrate all users at once using rake task:

```bash
cd /var/discourse
./launcher enter app
rake vkid:migrate_users
```

**Output:**
```
Starting VK ID migration...
============================================================
Found 1523 users to migrate.

..................................................
..................................................
(continues...)

============================================================
Migration completed!
✅ Successfully migrated: 1523 users
```

**Pros**: All users migrated immediately
**Cons**: Requires SSH/console access

### Step 5: Verify Migration

Check migration status:

```bash
cd /var/discourse
./launcher enter app
rake vkid:migration_status
```

**Expected output (after full migration):**
```
VK ID Migration Status
============================================================
Old provider (vkontakte): 0 users
New provider (vkid):      1523 users

✅ Migration complete! All users have been migrated to vkid.
```

### Step 6: Test Login

1. Open your Discourse site in **incognito/private window**
2. Click "Login"
3. Click "with VK ID" button
4. You should be redirected to VK ID (id.vk.ru)
5. Authorize and verify successful login

## Troubleshooting

### Issue: "redirect_uri_mismatch"

**Cause**: Callback URL doesn't match VK app settings.

**Solution**:
1. Check VK app settings at https://id.vk.com
2. Ensure redirect URI is exactly:
   ```
   https://your-site.com/auth/vkid/callback
   ```
3. Match http/https protocol
4. No trailing slash

### Issue: "invalid_request: code_verifier is missing"

**Cause**: PKCE not properly enabled.

**Solution**:
- Ensure you're using plugin v2.0+ (`git log` in plugin folder)
- Rebuild Discourse: `./launcher rebuild app`
- Clear browser cache/cookies

### Issue: Existing users can't login

**Cause**: UserAssociatedAccount still points to old provider.

**Solution**:
Run migration task:
```bash
rake vkid:migrate_users
```

Or wait for automatic migration on next login.

### Issue: No email returned

**Cause**: Email scope not granted.

**Solution**:
1. Check `vkid_scope` includes `email`
2. Verify VK app has email permission enabled
3. User must have email in their VK account

### Issue: Users see two VK login buttons

**Cause**: Both old and new settings enabled.

**Solution**:
1. Admin → Settings → Login
2. Uncheck `vk_auth_enabled` (old)
3. Keep only `vkid_enabled` checked

## Rollback (Emergency Only)

If you need to rollback to old plugin:

```bash
cd /var/discourse
./launcher enter app
rake vkid:rollback_migration
exit
./launcher rebuild app
```

Then:
1. Disable `vkid_enabled`
2. Enable `vk_auth_enabled`
3. Revert VK app redirect URI to `/vkontakte/callback`

**Warning**: Only rollback if absolutely necessary. VK ID is the future.

## Verification Checklist

After migration, verify:

- [ ] Users can login with VK ID
- [ ] New users can register via VK ID
- [ ] Existing VK users maintain their accounts (not duplicated)
- [ ] Avatar/email syncs correctly
- [ ] No error logs related to VK ID

Check logs:
```bash
tail -f /var/discourse/shared/standalone/log/rails/production.log | grep "VK ID"
```

## FAQ

### Do I need to inform users?

**No**. Migration is transparent:
- Existing users: Click "VK ID", auto-migrate, login works
- New users: Just works with VK ID
- No action required from users

### Will user data be lost?

**No**. Migration preserves:
- User account
- Posts/topics
- Settings
- All associations

Only `provider_name` changes: `vkontakte` → `vkid`

### Can I run migration multiple times?

**Yes**. Migration is idempotent:
- Already migrated accounts are skipped
- Safe to run multiple times
- No duplicate accounts created

### What happens to UserAssociatedAccount?

```ruby
# Before migration
UserAssociatedAccount.find(123)
# => provider_name: "vkontakte", provider_uid: "12345"

# After migration
UserAssociatedAccount.find(123)
# => provider_name: "vkid", provider_uid: "12345"
```

Only `provider_name` changes. All other data intact.

### How long does migration take?

**Automatic**: Gradual (days/weeks as users login)
**Bulk rake task**:
- 100 users: ~2 seconds
- 1,000 users: ~10 seconds
- 10,000 users: ~100 seconds

Very fast! Database update only.

## Support

Need help with migration?

- **Forum**: https://meta.discourse.org/t/vk-com-login-vkontakte/12987
- **Issues**: https://github.com/discourse/discourse-vk-auth/issues
- **VK ID Docs**: https://id.vk.ru/about/business/go/docs

## Success Stories

After migration, you'll have:

✅ Modern OAuth 2.1 with PKCE security
✅ Official VK ID (not deprecated VK OAuth)
✅ Better error handling and logging
✅ Automatic user migration
✅ Future-proof authentication

Welcome to VK ID! 🚀

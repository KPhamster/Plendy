# Quick Setup Guide: plendy.app Custom Domain

## 🎯 Goal
Stop password reset emails from going to spam by using your custom domain `plendy.app`.

---

## ⚡ Quick Steps (30 minutes of work, 2-4 hours total with DNS propagation)

### Step 1: Add DNS Records (5 minutes)

Go to wherever you manage `plendy.app` DNS (Namecheap, Cloudflare, Google Domains, etc.) and add:

#### SPF Record
```
Type: TXT
Host: @
Value: v=spf1 include:_spf.google.com include:_spf.firebasemail.com ~all
TTL: 3600
```

#### DMARC Record
```
Type: TXT
Host: _dmarc
Value: v=DMARC1; p=none; rua=mailto:dmarc@plendy.app
TTL: 3600
```

---

### Step 2: Connect Domain to Firebase (10 minutes)

1. Open [Firebase Console](https://console.firebase.google.com/)
2. Select **plendy-7df50** project
3. Go to **Hosting** (left sidebar)
4. Click **Add custom domain**
5. Enter: `plendy.app`
6. Click **Continue**

Firebase will give you:
- A TXT record for verification (add this to DNS)
- A records to point domain to Firebase (add these to DNS)

**Add these records to your DNS provider**, then click **Verify** in Firebase.

---

### Step 3: Add plendy.app to Authorized Domains (2 minutes)

1. Still in Firebase Console
2. Go to **Authentication** → **Settings** tab
3. Scroll to **Authorized domains**
4. Click **Add domain**
5. Enter: `plendy.app`
6. Click **Add**

---

### Step 4: Deploy Updated Firebase Config (2 minutes)

In your terminal:

```bash
firebase deploy --only hosting
```

This deploys the updated `firebase.json` that handles auth actions on your custom domain.

---

### Step 5: Wait & Test (1-48 hours)

**Wait for DNS propagation** (usually 1-2 hours, max 48 hours)

Check propagation status:
- Visit: https://dnschecker.org
- Enter: `plendy.app`
- Look for your A records to show up globally

**Once propagated:**
1. Open your app
2. Click "Forgot password?"
3. Enter your email
4. Check inbox (should NOT be in spam now!)
5. Verify the link goes to `plendy.app` (not `firebaseapp.com`)

---

## 📊 DNS Records Summary

You need these records in your DNS:

| Type | Host | Value | Why |
|------|------|-------|-----|
| TXT | @ | v=spf1 include:_spf.google.com include:_spf.firebasemail.com ~all | Email authentication |
| TXT | _dmarc | v=DMARC1; p=none; rua=mailto:dmarc@plendy.app | Email policy |
| TXT | @ | [From Firebase Console] | Domain verification |
| A | @ | [From Firebase Console] | Point to Firebase |
| A | @ | [From Firebase Console] | Redundant Firebase IP |

---

## ✅ Success Checklist

After DNS propagates:

- [ ] `https://plendy.app` loads your app
- [ ] Password reset email arrives in **inbox** (not spam)
- [ ] Email shows "From: Plendy"
- [ ] Reset link URL starts with `https://plendy.app`
- [ ] Clicking reset link works correctly
- [ ] Email headers show SPF: PASS and DMARC: PASS

---

## 🐛 Troubleshooting

### Domain not connecting?
- Wait longer (DNS can take 48 hours)
- Check with: https://dnschecker.org
- Make sure A records match Firebase exactly

### Emails still going to spam?
- Wait 24 hours after DNS setup
- Check email headers (View Source)
- Test with: https://mail-tester.com
- Try different email providers

### Reset link doesn't work?
- Clear browser cache
- Try incognito mode
- Redeploy: `firebase deploy --only hosting`

---

## 🎉 Expected Improvement

**Before:** 
- Email from: `noreply@plendy-7df50.firebaseapp.com`
- Link to: `https://plendy-7df50.firebaseapp.com/__/auth/action`
- Result: **Spam folder**

**After:**
- Email from: `Plendy <noreply@plendy-7df50.firebaseapp.com>` (sender name improved)
- Link to: `https://plendy.app/__/auth/action` (professional domain)
- Email authenticated with SPF/DMARC
- Result: **Inbox** ✨

---

## 📞 Where to Get Help

- **Firebase Custom Domains:** https://firebase.google.com/docs/hosting/custom-domain
- **DNS Checker:** https://dnschecker.org
- **Email Testing:** https://mail-tester.com
- **Full Guide:** See `CUSTOM_DOMAIN_SETUP.md` in this repo

---

## Next Steps After Setup

1. **Monitor email delivery** for a few days
2. **Test with multiple email providers** (Gmail, Outlook, Yahoo)
3. **After 1 week:** Update DMARC from `p=none` to `p=quarantine`
4. **After 1 month:** Consider `p=reject` for stricter policy

---

*Note: The sender address will still be `noreply@plendy-7df50.firebaseapp.com` because Firebase manages the actual email sending. The custom domain is used for the action URLs (reset links), which combined with SPF/DMARC significantly improves deliverability.*

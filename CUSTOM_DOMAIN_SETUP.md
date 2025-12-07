# Setting Up Custom Domain (plendy.app) for Firebase Email

## Goal
Configure `plendy.app` to handle Firebase Authentication emails, significantly improving deliverability and avoiding spam folders.

## Overview
This involves 3 main steps:
1. Configure DNS records for email authentication
2. Set up Firebase Hosting with custom domain
3. Configure custom action URL in Firebase Auth

---

## Step 1: Configure DNS Records

Go to your DNS provider (wherever you manage plendy.app) and add these records:

### 1.1 SPF Record (Protects against spoofing)

**Purpose:** Tells email providers that Firebase is allowed to send emails on behalf of plendy.app

```
Record Type: TXT
Host/Name: @ (or plendy.app)
Value: v=spf1 include:_spf.google.com include:_spf.firebasemail.com ~all
TTL: 3600 (or automatic)
```

**Note:** If you already have an SPF record, you need to **modify** it, not create a new one. Add `include:_spf.firebasemail.com` to your existing record.

Example if you already have SPF:
```
Existing: v=spf1 include:_spf.google.com ~all
Updated:  v=spf1 include:_spf.google.com include:_spf.firebasemail.com ~all
```

### 1.2 DMARC Record (Email authentication policy)

**Purpose:** Tells email providers what to do with emails that fail authentication

```
Record Type: TXT
Host/Name: _dmarc (or _dmarc.plendy.app)
Value: v=DMARC1; p=none; rua=mailto:dmarc@plendy.app
TTL: 3600 (or automatic)
```

**Note:** Start with `p=none` (monitoring mode). After testing, you can change to `p=quarantine` or `p=reject`.

### 1.3 DKIM Record (Coming from Firebase)

**Purpose:** Cryptographic signature to verify email authenticity

**You'll get this from Firebase after connecting your domain.** For now, skip this step - we'll come back to it.

---

## Step 2: Connect Custom Domain to Firebase Hosting

### 2.1 In Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: **plendy-7df50**
3. Navigate to **Hosting** (in left sidebar)
4. Click **Add custom domain**
5. Enter: `plendy.app`
6. Click **Continue**

### 2.2 Verify Domain Ownership

Firebase will ask you to verify domain ownership:

**Option A: TXT Record Verification (Recommended)**
```
Record Type: TXT
Host/Name: @ (or plendy.app)
Value: [Firebase will provide this - looks like: google-site-verification=abc123...]
TTL: 3600
```

Add this record to your DNS, then click **Verify** in Firebase Console.

**Option B: File Upload Verification**
- Download the verification file from Firebase
- Upload to your web hosting root
- Click **Verify**

### 2.3 Point Domain to Firebase

After verification, Firebase will provide DNS records to point your domain to Firebase Hosting:

**For Root Domain (plendy.app):**
```
Record Type: A
Host/Name: @
Value: 151.101.1.195
TTL: 3600

Record Type: A
Host/Name: @
Value: 151.101.65.195
TTL: 3600
```

**For www subdomain (optional - www.plendy.app):**
```
Record Type: CNAME
Host/Name: www
Value: plendy-7df50.web.app
TTL: 3600
```

**Note:** Firebase may provide different IP addresses. Use the ones shown in your Firebase Console.

### 2.4 Wait for Propagation

- DNS changes can take 24-48 hours to propagate
- Usually happens within 1-2 hours
- Check status in Firebase Console (it will show "Connected" when ready)

---

## Step 3: Configure Custom Action URL in Firebase Auth

After your custom domain is connected to Firebase Hosting:

### 3.1 Update Authentication Action URL

1. Firebase Console → **Authentication** → **Settings** tab
2. Scroll down to **Authorized domains**
3. Click **Add domain**
4. Add: `plendy.app`
5. Click **Add**

### 3.2 Update Email Templates with Custom Action URL

1. Firebase Console → **Authentication** → **Templates** tab
2. Click **Password reset** template
3. Click **Customize action URL** (if available)
4. Change from `https://plendy-7df50.firebaseapp.com/__/auth/action`
5. To: `https://plendy.app/__/auth/action`
6. Click **Save**

**Note:** Some Firebase plans may not show "Customize action URL" directly in the UI. The action URL may automatically use your custom domain once it's connected.

---

## Step 4: Create Auth Handler Page (Optional but Recommended)

Create a custom landing page for password reset at `https://plendy.app/auth/action`

### 4.1 Update firebase.json

Your `firebase.json` already has hosting configured. Add a rewrite for auth actions:

```json
"rewrites": [
  { 
    "source": "/auth/action", 
    "destination": "/index.html" 
  },
  { 
    "source": "/api/publicShare", 
    "function": { "functionId": "publicShare", "region": "us-central1" } 
  },
  { 
    "source": "**", 
    "destination": "/index.html" 
  }
]
```

### 4.2 Handle Auth Actions in Your App

Your Flutter web app should already handle Firebase Auth actions. Verify this is working by testing the password reset flow.

---

## Step 5: Update Firestore Security Rules (If Needed)

Ensure your Firestore rules allow access from both domains:

```javascript
// This should already be configured, but verify:
service cloud.firestore {
  match /databases/{database}/documents {
    // Your existing rules...
  }
}
```

No changes needed here - Firebase Auth handles this automatically.

---

## Step 6: Testing

### 6.1 Test Password Reset Flow

1. In your app, click "Forgot password?"
2. Enter an email address
3. Check the email you receive
4. Verify:
   - [ ] Email arrives in inbox (not spam)
   - [ ] Sender shows as "Plendy"
   - [ ] Reset link goes to `plendy.app` (not `plendy-7df50.firebaseapp.com`)
   - [ ] Clicking link opens your app correctly
   - [ ] Password reset works successfully

### 6.2 Test with Multiple Email Providers

- [ ] Gmail
- [ ] Outlook/Hotmail
- [ ] Yahoo Mail
- [ ] Apple Mail (iCloud)
- [ ] ProtonMail

### 6.3 Check Email Headers

1. Open the password reset email
2. View full email headers (usually "Show original" or "View source")
3. Look for:
   - `SPF: PASS`
   - `DKIM: PASS`
   - `DMARC: PASS`

---

## DNS Records Summary for plendy.app

Here's a complete list of DNS records you need to add:

| Type | Host/Name | Value | TTL | Purpose |
|------|-----------|-------|-----|---------|
| TXT | @ | v=spf1 include:_spf.google.com include:_spf.firebasemail.com ~all | 3600 | SPF |
| TXT | _dmarc | v=DMARC1; p=none; rua=mailto:dmarc@plendy.app | 3600 | DMARC |
| TXT | @ | [Firebase verification code] | 3600 | Domain verification |
| A | @ | 151.101.1.195 | 3600 | Firebase Hosting |
| A | @ | 151.101.65.195 | 3600 | Firebase Hosting |
| CNAME | www | plendy-7df50.web.app | 3600 | WWW redirect |

**Note:** Firebase will provide exact values for verification and A records. Use those instead of the examples above.

---

## Common DNS Providers - Where to Make Changes

### Namecheap
1. Log in to Namecheap
2. Dashboard → Domain List → Manage
3. Advanced DNS tab
4. Add records

### Google Domains / Cloudflare / GoDaddy
1. Log in to your provider
2. Find DNS management section
3. Add records as specified above

### Cloudflare (Recommended for Performance)
- If using Cloudflare, disable proxy (grey cloud) for A records initially
- After setup is working, you can enable it

---

## Troubleshooting

### Emails Still Going to Spam After Setup
- Wait 24-48 hours after DNS changes
- Check email headers for SPF/DKIM/DMARC status
- Use [mail-tester.com](https://www.mail-tester.com/) to test email quality
- Consider gradually increasing email volume (start small)

### Custom Domain Not Connecting
- DNS propagation can take up to 48 hours
- Check DNS records with [dnschecker.org](https://dnschecker.org/)
- Verify A records are pointing to correct Firebase IPs
- Make sure you don't have conflicting DNS records

### Password Reset Link Doesn't Work
- Clear browser cache
- Verify action URL in Firebase Console
- Check that firebase.json has correct rewrites
- Test in incognito/private browsing mode

### Email Authentication Failing
- SPF: Must include both Google and Firebase SPF records
- DKIM: Wait for Firebase to propagate keys (can take time)
- DMARC: Start with `p=none` for monitoring
- Check with [mxtoolbox.com/SuperTool](https://mxtoolbox.com/SuperTool.aspx)

---

## Timeline

| Task | Time Required |
|------|---------------|
| Adding DNS records | 5-10 minutes |
| DNS propagation | 1-48 hours |
| Firebase domain verification | 5-15 minutes |
| Connecting Firebase Hosting | 5 minutes |
| SSL certificate provisioning | 10-30 minutes (automatic) |
| Testing email flow | 10 minutes |

**Total estimated time:** 2-4 hours (mostly waiting for DNS)

---

## Security Notes

1. **Start with DMARC p=none** - Monitor reports before enforcing
2. **Keep SPF record under 10 lookups** - Firebase already counts as 1
3. **Don't share DKIM private keys** - Firebase manages these
4. **Monitor email reputation** - Check delivery rates regularly
5. **Set up email alerts** - Get notified of authentication failures

---

## After Setup - Best Practices

1. **Monitor Deliverability:**
   - Track bounce rates
   - Monitor spam complaints
   - Check inbox placement rates

2. **Regular Testing:**
   - Test password reset monthly
   - Try different email providers
   - Check email headers periodically

3. **Keep DNS Records Updated:**
   - Document all changes
   - Review records quarterly
   - Update if Firebase changes requirements

4. **Email Reputation:**
   - Remove invalid emails promptly
   - Don't send too many emails at once
   - Respond to user complaints quickly

---

## Resources

- [Firebase Custom Domain Setup](https://firebase.google.com/docs/hosting/custom-domain)
- [SPF Record Checker](https://mxtoolbox.com/spf.aspx)
- [DMARC Analyzer](https://dmarc.org/resources/specification/)
- [Email Header Analyzer](https://mxtoolbox.com/EmailHeaders.aspx)
- [DNS Propagation Checker](https://www.whatsmydns.net/)
- [Email Deliverability Test](https://www.mail-tester.com/)

---

## Quick Start Checklist

- [ ] Add SPF record to DNS
- [ ] Add DMARC record to DNS
- [ ] Add plendy.app to Firebase Hosting
- [ ] Verify domain ownership
- [ ] Point A records to Firebase
- [ ] Wait for DNS propagation
- [ ] Add plendy.app to authorized domains
- [ ] Test password reset flow
- [ ] Check email lands in inbox (not spam)
- [ ] Verify all email providers

---

## Need Help?

If you run into issues:
1. Check DNS records with online tools
2. Review Firebase Console for error messages
3. Test with [mail-tester.com](https://www.mail-tester.com/)
4. Check Firebase documentation for updates

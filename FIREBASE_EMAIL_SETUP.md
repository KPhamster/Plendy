# Firebase Email Setup - Avoiding Spam Folder

## Problem
Password reset emails from Firebase Auth are going to spam folder because they come from `noreply@plendy-7df50.firebaseapp.com`, which lacks proper email authentication and branding.

## Solutions (In Order of Priority)

### 1. Customize Email Template (Do This First) ⭐

**Steps:**
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **plendy-7df50**
3. Navigate to **Authentication** → **Templates** tab
4. Click on **Password reset** template
5. Click **Edit template**
6. Update the following:

**Sender Name:**
```
Plendy <noreply@plendy-7df50.firebaseapp.com>
```

**Email Subject:**
```
Reset your Plendy password
```

**Email Body:** (Customize with your branding)
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { text-align: center; padding: 20px 0; }
    .button { display: inline-block; padding: 12px 30px; background-color: #000; color: #fff; text-decoration: none; border-radius: 25px; margin: 20px 0; }
    .footer { color: #666; font-size: 12px; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Reset Your Password</h1>
    </div>
    <p>Hello,</p>
    <p>We received a request to reset your Plendy account password. Click the button below to reset it:</p>
    <p style="text-align: center;">
      <a href="%LINK%" class="button">Reset Password</a>
    </p>
    <p>If you didn't request a password reset, you can safely ignore this email.</p>
    <p>This link will expire in 1 hour.</p>
    <div class="footer">
      <p>© 2025 Plendy - Discover. Plan. Experience.</p>
      <p>If the button doesn't work, copy and paste this link into your browser:<br>%LINK%</p>
    </div>
  </div>
</body>
</html>
```

7. Click **Save**

### 2. Set Up Custom Domain (Recommended for Production) 🌟

This is the **best long-term solution** to avoid spam folders.

**Requirements:**
- Own a domain (e.g., `plendy.com`)
- Access to DNS settings

**Steps:**

#### A. Purchase/Use Your Domain
- Buy a domain from providers like Namecheap, Google Domains, Cloudflare, etc.
- Or use an existing domain

#### B. Set Up DNS Records
Add these DNS records to your domain:

**SPF Record (TXT):**
```
Host: @
Type: TXT
Value: v=spf1 include:_spf.firebasemail.com ~all
```

**DKIM Record:**
Firebase will provide this after you set up custom email in the console.

**DMARC Record (TXT):**
```
Host: _dmarc
Type: TXT
Value: v=DMARC1; p=none; rua=mailto:dmarc@yourdomain.com
```

#### C. Configure in Firebase
1. Firebase Console → **Authentication** → **Templates**
2. Look for **Customize action URL** or **Email provider settings**
3. Add your custom domain
4. Follow Firebase's verification process

**Action URL Example:**
```
https://plendy.com/auth/action
```

#### D. Update Hosting Config (Already set up in `firebase.json`)
Your hosting is already configured, but make sure your domain points to Firebase Hosting.

### 3. Use a Dedicated Email Service (Advanced) 🚀

For the **most reliable** email delivery, use services like SendGrid, Mailgun, or AWS SES.

**This requires:**
1. Setting up a Cloud Function to handle password resets
2. Custom email templates
3. Managing email reputation
4. Monitoring deliverability

**Example Cloud Function Structure:**
```javascript
// functions/src/sendPasswordReset.js
const functions = require('firebase-functions');
const sgMail = require('@sendgrid/mail');

exports.sendPasswordReset = functions.https.onCall(async (data, context) => {
  // Verify user is authenticated
  // Generate password reset link
  // Send via SendGrid
});
```

**Cost:** Most email services have free tiers (10k-100k emails/month free)

## Immediate Actions You Can Take Now ✅

1. **Tell users to check spam** (Already done in code)
   - Dialog warns users about spam folder
   - Success message reminds users to check spam

2. **Customize Firebase email template** (Do this today)
   - Takes 5 minutes
   - Significant improvement
   - No code changes needed

3. **Set up custom domain** (Do this soon)
   - Best long-term solution
   - Professional appearance
   - Highest deliverability

## Testing Email Deliverability

After making changes, test with multiple email providers:
- Gmail
- Outlook/Hotmail
- Yahoo
- Apple Mail (iCloud)
- ProtonMail

Check:
- [ ] Arrives in inbox (not spam)
- [ ] Email looks professional
- [ ] Links work correctly
- [ ] Sender name is "Plendy" not a random address

## Additional Tips

1. **Build Email Reputation:**
   - Start with small batches
   - Monitor bounce rates
   - Remove invalid emails promptly

2. **Monitor Firebase Quota:**
   - Firebase has email sending limits
   - Monitor usage in Console

3. **Add Unsubscribe Option:**
   - Even though these are transactional emails, it helps with spam filters

4. **Use HTTPS:**
   - All links should be HTTPS (already done)

## Resources

- [Firebase Auth Email Customization](https://firebase.google.com/docs/auth/custom-email-handler)
- [SPF Record Setup](https://support.google.com/a/answer/33786)
- [DMARC Overview](https://dmarc.org/)
- [Email Deliverability Best Practices](https://sendgrid.com/blog/email-deliverability-best-practices/)

## Status

- [x] Code warns users about spam folder
- [x] Firebase email template customized
- [x] Custom domain available (plendy.app)
- [ ] DNS records configured
- [ ] Custom action URL configured in Firebase
- [ ] Firebase Hosting connected to custom domain
- [ ] Tested across email providers

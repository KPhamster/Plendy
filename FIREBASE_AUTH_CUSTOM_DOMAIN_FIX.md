# CRITICAL FIX: Firebase Authentication Custom Domain

## ⚠️ The Real Problem

Firebase Authentication has a **separate** custom domain feature for emails that's different from Firebase Hosting custom domains. This is what actually fixes spam issues!

## 🎯 What We Missed

We set up:
- ✅ Custom email template (branding)
- ✅ Firebase Hosting with custom domain
- ✅ Custom action URLs

**What we DIDN'T set up:**
- ❌ **Custom Domain in Authentication > Templates** (This is the key!)

## 🔧 The Real Solution

### Option 1: Custom Domain in Firebase Auth (Recommended but Limited)

**NOTE:** This feature is only available in **Firebase Blaze (paid) plan** and requires manual setup through Firebase support.

1. Go to Firebase Console → **Authentication** → **Templates**
2. Look for **"Customize domain"** or **"Custom email domain"** section
3. Click **"Add custom domain"** or **"Set up custom domain"**
4. Follow Firebase's instructions to:
   - Verify domain ownership
   - Add DKIM records (Firebase will provide these)
   - Configure email sending from your domain

**This will make emails actually come FROM `noreply@plendy.app` instead of `noreply@plendy-7df50.firebaseapp.com`**

### Option 2: Use Custom SMTP Server (Most Reliable) ⭐

This is the **best solution** that works for everyone:

#### Step 1: Choose an Email Service Provider

Pick one:
- **SendGrid** (100 emails/day free)
- **Mailgun** (5,000 emails/month free first 3 months)
- **AWS SES** (62,000 emails/month free)
- **Resend** (3,000 emails/month free, developer-friendly)

**Recommendation: SendGrid or Resend** (easiest setup)

#### Step 2: Set Up SendGrid (Example)

1. **Sign up for SendGrid:**
   - Go to https://sendgrid.com
   - Create free account
   - Verify your email

2. **Verify Your Domain (plendy.app):**
   - SendGrid Dashboard → Settings → Sender Authentication
   - Click "Authenticate Your Domain"
   - Enter: `plendy.app`
   - SendGrid provides DNS records (CNAME records for DKIM, SPF)
   
3. **Add DNS Records SendGrid Provides:**
   ```
   # Example - SendGrid will give you specific values
   Type: CNAME
   Host: s1._domainkey
   Value: s1.domainkey.u123456.wl.sendgrid.net
   
   Type: CNAME  
   Host: s2._domainkey
   Value: s2.domainkey.u123456.wl.sendgrid.net
   
   # And more...
   ```

4. **Create API Key:**
   - SendGrid → Settings → API Keys
   - Click "Create API Key"
   - Name it: "Plendy Password Reset"
   - Permissions: "Full Access" or "Mail Send"
   - Copy the API key (you'll need it)

5. **Set Up Cloud Function:**

Create `/functions/src/sendPasswordReset.js`:

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const sgMail = require('@sendgrid/mail');

// Initialize if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

// Set SendGrid API key from environment variable
sgMail.setApiKey(functions.config().sendgrid.key);

exports.sendPasswordResetEmail = functions.https.onCall(async (data, context) => {
  // Security: Only allow authenticated users or specific conditions
  const { email } = data;
  
  if (!email) {
    throw new functions.https.HttpsError('invalid-argument', 'Email is required');
  }

  try {
    // Generate password reset link using Firebase Admin SDK
    const link = await admin.auth().generatePasswordResetLink(email, {
      url: 'https://plendy.app', // Where to redirect after reset
    });

    // Send email via SendGrid
    const msg = {
      to: email,
      from: {
        email: 'noreply@plendy.app',
        name: 'Plendy'
      },
      subject: 'Reset your Plendy password',
      html: `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { 
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
              line-height: 1.6; 
              color: #333;
              background-color: #f5f5f5;
            }
            .container { 
              max-width: 600px; 
              margin: 40px auto; 
              background: white;
              border-radius: 8px;
              overflow: hidden;
              box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            }
            .header { 
              text-align: center; 
              padding: 40px 20px;
              background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
              color: white;
            }
            .header h1 {
              margin: 0;
              font-size: 28px;
              font-weight: 600;
            }
            .header p {
              margin: 8px 0 0 0;
              font-size: 14px;
              opacity: 0.9;
            }
            .content {
              padding: 40px 30px;
            }
            .button { 
              display: inline-block; 
              padding: 14px 40px; 
              background-color: #000; 
              color: #fff !important; 
              text-decoration: none; 
              border-radius: 25px; 
              margin: 20px 0;
              font-weight: 600;
              font-size: 16px;
            }
            .button-wrapper {
              text-align: center;
              margin: 30px 0;
            }
            .footer { 
              background: #f8f9fa;
              padding: 30px;
              text-align: center;
              color: #666; 
              font-size: 13px;
              border-top: 1px solid #e9ecef;
            }
            .footer a {
              color: #667eea;
              text-decoration: none;
            }
            .security-note {
              background: #fff3cd;
              border-left: 4px solid #ffc107;
              padding: 15px;
              margin: 20px 0;
              font-size: 14px;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h1>Reset Your Password</h1>
              <p>DISCOVER. PLAN. EXPERIENCE.</p>
            </div>
            
            <div class="content">
              <p>Hello,</p>
              
              <p>We received a request to reset your Plendy account password. Click the button below to create a new password:</p>
              
              <div class="button-wrapper">
                <a href="${link}" class="button">Reset Password</a>
              </div>
              
              <div class="security-note">
                <strong>⚠️ Security Notice:</strong>
                <ul style="margin: 10px 0; padding-left: 20px;">
                  <li>This link expires in <strong>1 hour</strong></li>
                  <li>If you didn't request this, you can safely ignore this email</li>
                  <li>Your password won't change until you create a new one</li>
                </ul>
              </div>
              
              <p style="color: #666; font-size: 14px; margin-top: 30px;">
                Having trouble with the button? Copy and paste this link into your browser:
                <br>
                <a href="${link}" style="color: #667eea; word-break: break-all;">${link}</a>
              </p>
            </div>
            
            <div class="footer">
              <p><strong>Plendy</strong></p>
              <p>Discover. Plan. Experience.</p>
              <p style="margin-top: 15px;">
                Questions? Contact us at <a href="mailto:support@plendy.app">support@plendy.app</a>
              </p>
            </div>
          </div>
        </body>
        </html>
      `,
      // Plain text version for email clients that don't support HTML
      text: `
Reset Your Password

Hello,

We received a request to reset your Plendy account password. Click the link below to create a new password:

${link}

This link expires in 1 hour.

If you didn't request this password reset, you can safely ignore this email. Your password won't change until you create a new one.

---
Plendy - Discover. Plan. Experience.
Questions? Contact us at support@plendy.app
      `.trim(),
    };

    await sgMail.send(msg);
    
    return { success: true, message: 'Password reset email sent successfully' };
  } catch (error) {
    console.error('Error sending password reset email:', error);
    throw new functions.https.HttpsError('internal', 'Failed to send email');
  }
});
```

6. **Install SendGrid Package:**

```bash
cd functions
npm install @sendgrid/mail
```

7. **Set SendGrid API Key in Firebase:**

```bash
firebase functions:config:set sendgrid.key="YOUR_SENDGRID_API_KEY"
```

8. **Deploy Function:**

```bash
firebase deploy --only functions:sendPasswordResetEmail
```

#### Step 3: Update Flutter App to Use Cloud Function

Replace the `sendPasswordResetEmail` in `lib/services/auth_service.dart`:

```dart
// Send Password Reset Email via Cloud Function
Future<void> sendPasswordResetEmail(String email) async {
  try {
    print('DEBUG: Attempting to send password reset email to: $email');
    
    // Call Cloud Function instead of Firebase Auth directly
    final callable = FirebaseFunctions.instance.httpsCallable('sendPasswordResetEmail');
    final result = await callable.call({
      'email': email,
    });
    
    print('DEBUG: Password reset email sent successfully to: $email');
    print('Result: ${result.data}');
  } on FirebaseFunctionsException catch (e) {
    print('DEBUG: Cloud Function error: ${e.code} - ${e.message}');
    
    String message;
    switch (e.code) {
      case 'invalid-argument':
        message = 'Please enter a valid email address.';
        break;
      case 'not-found':
        message = 'No account found with this email address.';
        break;
      default:
        message = e.message ?? 'Failed to send reset email. Please try again.';
    }
    throw Exception(message);
  } catch (e) {
    print('DEBUG: Generic error during password reset: $e');
    throw Exception('Failed to send reset email. Please try again.');
  }
}
```

9. **Add Firebase Functions package to pubspec.yaml:**

```yaml
dependencies:
  cloud_functions: ^5.1.3  # Add this
```

Then run:
```bash
flutter pub get
```

#### Step 4: Test

1. Request password reset
2. Check inbox (should arrive in **inbox**, not spam!)
3. Email should show:
   - From: `Plendy <noreply@plendy.app>`
   - Beautiful HTML template
   - Working reset link

---

## 🎯 Why This Works

**Using SendGrid/Custom SMTP:**
- ✅ Emails actually come FROM `noreply@plendy.app`
- ✅ Proper DKIM, SPF, DMARC authentication
- ✅ SendGrid has excellent email reputation
- ✅ Better deliverability tracking
- ✅ More control over email content
- ✅ Works on Firebase Spark (free) plan

**vs Firebase Default:**
- ❌ Emails come from `firebaseapp.com`
- ❌ Poor email reputation
- ❌ Limited customization
- ❌ No deliverability insights

---

## 💰 Cost Comparison

| Service | Free Tier | Cost After |
|---------|-----------|------------|
| SendGrid | 100/day forever | $15/mo for 40k |
| Mailgun | 5k/mo (3 months) | $35/mo for 50k |
| AWS SES | 62k/mo (12 months) | $0.10 per 1k |
| Resend | 3k/mo forever | $20/mo for 50k |

**For your app:** Start with SendGrid free tier (100/day = 3,000/month)

---

## 🚀 Quick Start Commands

```bash
# 1. Install dependencies
cd functions
npm install @sendgrid/mail firebase-admin firebase-functions

# 2. Set SendGrid API key
firebase functions:config:set sendgrid.key="YOUR_API_KEY_HERE"

# 3. Deploy function
firebase deploy --only functions:sendPasswordResetEmail

# 4. Add to Flutter
flutter pub add cloud_functions
flutter pub get
```

---

## ✅ Testing Checklist

After setup:
- [ ] Request password reset
- [ ] Email arrives in inbox (NOT spam)
- [ ] From shows "Plendy <noreply@plendy.app>"
- [ ] Email looks professional
- [ ] Reset link works
- [ ] Test with Gmail, Outlook, Yahoo
- [ ] Check email headers: SPF PASS, DKIM PASS, DMARC PASS

---

## 🎉 Expected Result

**Before (Firebase Default):**
```
From: noreply@plendy-7df50.firebaseapp.com
To: kevinphamster@gmail.com
Subject: Reset your password

[Generic Firebase template]

📍 Location: SPAM FOLDER
```

**After (SendGrid + Custom Domain):**
```
From: Plendy <noreply@plendy.app>
To: kevinphamster@gmail.com
Subject: Reset your Plendy password

[Beautiful branded HTML email]

📍 Location: INBOX ✨
Authentication: SPF ✅ DKIM ✅ DMARC ✅
```

---

## 📚 Resources

- [SendGrid Setup Guide](https://docs.sendgrid.com/for-developers/sending-email/quickstart-nodejs)
- [Firebase Admin SDK](https://firebase.google.com/docs/auth/admin/email-action-links)
- [Firebase Functions](https://firebase.google.com/docs/functions)
- [Email Deliverability Testing](https://www.mail-tester.com/)

---

## 🆘 Need Help?

Common issues:
- **Function not deploying?** Check `functions/package.json` has correct dependencies
- **API key not working?** Double-check it's set correctly with `firebase functions:config:get`
- **Emails still spam?** Wait 24-48 hours for SendGrid domain authentication to propagate
- **Link not working?** Check `url` parameter in `generatePasswordResetLink`

---

**This is the REAL fix. Custom SMTP + proper domain authentication = inbox delivery! 🎯**

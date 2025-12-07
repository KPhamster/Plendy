# 🚀 Setup SendGrid - Fix Spam Folder Issue

## ✅ What I've Done

I've already prepared all the code. You just need to:
1. Sign up for SendGrid (5 minutes)
2. Get API key (2 minutes)
3. Run a few commands (3 minutes)

**Total time: ~10 minutes**

---

## 📋 Step-by-Step Instructions

### Step 1: Sign Up for SendGrid (5 minutes)

1. Go to https://signup.sendgrid.com/
2. Click **"Start for Free"**
3. Fill in:
   - Email: (your email)
   - Password: (create one)
   - Click **"Create Account"**
4. Verify your email address
5. Complete the onboarding:
   - Choose **"Integrate using our Web API or SMTP Relay"**
   - Skip the rest for now

### Step 2: Get SendGrid API Key (2 minutes)

1. In SendGrid Dashboard, click **Settings** (left sidebar)
2. Click **API Keys**
3. Click **"Create API Key"** (top right, blue button)
4. Fill in:
   - API Key Name: `Plendy Password Reset`
   - API Key Permissions: Select **"Full Access"**
5. Click **"Create & View"**
6. **COPY THE API KEY** - You'll only see this once!
   - It looks like: `SG.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
   - Save it somewhere safe (you'll use it in Step 4)

### Step 3: Verify Your Domain in SendGrid (5 minutes)

1. In SendGrid Dashboard, go to **Settings** → **Sender Authentication**
2. Click **"Authenticate Your Domain"**
3. Select your DNS provider (e.g., Namecheap, Cloudflare, GoDaddy)
4. Enter your domain: `plendy.app`
5. SendGrid will show you DNS records to add
6. **Add these DNS records to your domain:**

   Go to your DNS provider and add the records SendGrid provides (example):

   ```
   Type: CNAME
   Host: s1._domainkey
   Value: s1.domainkey.u12345678.wl123.sendgrid.net
   
   Type: CNAME
   Host: s2._domainkey
   Value: s2.domainkey.u12345678.wl123.sendgrid.net
   
   Type: CNAME
   Host: em1234
   Value: u12345678.wl123.sendgrid.net
   ```

7. After adding DNS records, click **"Verify"** in SendGrid
8. Wait for verification (can take up to 48 hours, usually 10-30 minutes)

### Step 4: Configure Firebase with SendGrid API Key (2 minutes)

Open your terminal and run:

```bash
cd /Users/kevinpham/Documents/GitHub/Plendy

# Set the SendGrid API key in Firebase
firebase functions:config:set sendgrid.key="PASTE_YOUR_API_KEY_HERE"
```

Replace `PASTE_YOUR_API_KEY_HERE` with the API key you copied in Step 2.

### Step 5: Install Dependencies (2 minutes)

```bash
# Install SendGrid package for Cloud Functions
cd functions
npm install

# Go back to project root
cd ..

# Install Flutter dependencies
flutter pub get
```

### Step 6: Deploy Cloud Function (2 minutes)

```bash
# Deploy the new password reset function
firebase deploy --only functions:sendPasswordResetEmail
```

Wait for deployment to complete (usually 1-2 minutes).

### Step 7: Test It! (2 minutes)

1. Run your app:
   ```bash
   flutter run
   ```

2. Click **"Forgot password?"**
3. Enter your email: `kevinphamster@gmail.com`
4. Click **"Send Reset Email"**
5. Check your inbox (NOT spam folder!)

---

## ✨ Expected Result

**Before:**
- Email from: `noreply@plendy-7df50.firebaseapp.com`
- Location: **SPAM FOLDER** 📭
- Authentication: None

**After:**
- Email from: `Plendy <noreply@plendy.app>`
- Location: **INBOX** ✅
- Authentication: SPF ✅ DKIM ✅ DMARC ✅
- Beautiful branded HTML email

---

## 🐛 Troubleshooting

### Function deployment fails?
```bash
# Check you're in the right directory
pwd
# Should show: /Users/kevinpham/Documents/GitHub/Plendy

# Try deploying again
firebase deploy --only functions:sendPasswordResetEmail
```

### "SendGrid API key not configured" error?
```bash
# Verify the API key was set
firebase functions:config:get

# Should show:
# {
#   "sendgrid": {
#     "key": "SG.xxxxx..."
#   }
# }

# If not set, run this again:
firebase functions:config:set sendgrid.key="YOUR_API_KEY"
```

### Email still not arriving?
1. Check SendGrid Activity (Dashboard → Activity)
2. Verify domain authentication is complete (green checkmark)
3. Wait 10-30 minutes after adding DNS records
4. Check spam folder one more time (it may take 24 hours for full propagation)

### Domain verification stuck?
1. Double-check DNS records match exactly what SendGrid provided
2. Use https://dnschecker.org to verify records propagated
3. Wait longer (DNS can take up to 48 hours)
4. Try clicking "Verify" again in SendGrid

---

## 📊 Verify It's Working

### Check Email Headers
1. Receive the password reset email
2. Open it
3. Click "Show original" or "View source"
4. Look for:
   ```
   spf=pass
   dkim=pass
   dmarc=pass
   from: noreply@plendy.app
   ```

### Check SendGrid Dashboard
1. Go to SendGrid → Activity
2. You should see your sent email
3. Status should be "Delivered"

### Test Email Quality
1. Forward the email to: check@mail-tester.com
2. Go to https://www.mail-tester.com
3. Check your score (should be 8-10/10)

---

## 💰 Cost

**SendGrid Free Tier:**
- 100 emails per day
- Forever free
- No credit card required initially

**If you exceed 100/day:**
- Essentials Plan: $15/month for 40,000 emails
- Pro Plan: $90/month for 100,000 emails

**For your app:** 100/day = 3,000/month is plenty for getting started!

---

## ✅ Success Checklist

- [ ] Signed up for SendGrid
- [ ] Created API key
- [ ] Added DNS records to plendy.app
- [ ] Verified domain in SendGrid (green checkmark)
- [ ] Set API key in Firebase: `firebase functions:config:set sendgrid.key="..."`
- [ ] Installed dependencies: `npm install` in functions folder
- [ ] Ran `flutter pub get`
- [ ] Deployed function: `firebase deploy --only functions:sendPasswordResetEmail`
- [ ] Tested password reset flow
- [ ] Email arrived in inbox (not spam!)
- [ ] Email shows "From: Plendy <noreply@plendy.app>"
- [ ] Reset link works correctly

---

## 🎉 You're Done!

Once completed, your password reset emails will:
- ✅ Land in inbox (not spam)
- ✅ Look professional and branded
- ✅ Have proper email authentication
- ✅ Be fully tracked in SendGrid
- ✅ Work reliably across all email providers

---

## 📞 Need Help?

Common commands:
```bash
# Check function logs
firebase functions:log --only sendPasswordResetEmail

# Check config
firebase functions:config:get

# Redeploy function
firebase deploy --only functions:sendPasswordResetEmail

# Test locally (optional)
cd functions
npm run serve
```

---

## 🔄 Rollback (If Needed)

If something goes wrong, you can rollback to Firebase's default:

1. Comment out the cloud function call in `auth_service.dart`
2. Uncomment the original `_auth.sendPasswordResetEmail()` code
3. Run `flutter pub get` and restart app

But trust me, SendGrid works better! 🚀

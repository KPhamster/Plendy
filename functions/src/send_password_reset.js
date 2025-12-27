const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const sgMail = require("@sendgrid/mail");

/**
 * Cloud Function to send password reset emails via SendGrid
 * This bypasses Firebase's default email system for better deliverability
 *
 * To configure SendGrid API key:
 * firebase functions:secrets:set SENDGRID_API_KEY
 */
exports.sendPasswordResetEmail = onCall(async (request) => {
  const { email } = request.data;

  // Get SendGrid API key from environment
  const apiKey = process.env.SENDGRID_API_KEY;
  if (apiKey) {
    sgMail.setApiKey(apiKey);
  }

  // Validate input
  if (!email || typeof email !== "string") {
    throw new HttpsError(
      "invalid-argument",
      "Email address is required and must be a string",
    );
  }

  // Basic email validation
  const emailRegex = /^\S+@\S+\.\S+$/;
  if (!emailRegex.test(email)) {
    throw new HttpsError(
      "invalid-argument",
      "Please enter a valid email address",
    );
  }

  try {
    // Check if SendGrid is configured
    if (!apiKey) {
      console.error("SendGrid API key not configured");
      throw new HttpsError(
        "failed-precondition",
        "Email service not configured. Please contact support.",
      );
    }

    // Verify user exists in Firebase Auth
    let userExists = true;
    try {
      await admin.auth().getUserByEmail(email);
    } catch (error) {
      if (error.code === "auth/user-not-found") {
        userExists = false;
      }
    }

    if (!userExists) {
      // For security, we still return success even if user doesn't exist
      // This prevents email enumeration attacks
      console.log(`Password reset requested for non-existent user: ${email}`);
      return {
        success: true,
        message: "If an account exists with this email, a password reset link has been sent.",
      };
    }

    // Generate password reset link
    const link = await admin.auth().generatePasswordResetLink(email, {
      url: "https://plendy.app", // Redirect URL after password reset
    });

    console.log(`Generated password reset link for: ${email}`);

    // Send email via SendGrid
    const msg = {
      to: email,
      from: {
        email: "noreply@plendy.app",
        name: "Plendy",
      },
      subject: "Reset your Plendy password",
      html: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { 
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
      line-height: 1.6; 
      color: #333;
      background-color: #f5f5f5;
      margin: 0;
      padding: 0;
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
      letter-spacing: 1px;
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
    .button:hover {
      background-color: #333;
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
    .security-note ul {
      margin: 10px 0;
      padding-left: 20px;
    }
    .link-fallback {
      color: #666;
      font-size: 14px;
      margin-top: 30px;
      padding: 15px;
      background: #f8f9fa;
      border-radius: 4px;
      word-break: break-all;
    }
    .link-fallback a {
      color: #667eea;
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
      
      <p>We received a request to reset your Plendy account password. 
      Click the button below to create a new password:</p>
      
      <div class="button-wrapper">
        <a href="${link}" class="button">Reset Password</a>
      </div>
      
      <div class="security-note">
        <strong>⚠️ Security Notice:</strong>
        <ul>
          <li>This link expires in <strong>1 hour</strong></li>
          <li>If you didn't request this, you can safely ignore this email</li>
          <li>Your password won't change until you create a new one</li>
        </ul>
      </div>
      
      <div class="link-fallback">
        <p style="margin-top: 0;"><strong>Having trouble with the button?</strong></p>
        <p style="margin-bottom: 0;">Copy and paste this link into your browser:</p>
        <p><a href="${link}">${link}</a></p>
      </div>
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
      // Plain text version
      text: `
Reset Your Password

Hello,

We received a request to reset your Plendy account password. Click the link below to create a new password:

${link}

SECURITY NOTICE:
- This link expires in 1 hour
- If you didn't request this, you can safely ignore this email
- Your password won't change until you create a new one

---
Plendy - Discover. Plan. Experience.
Questions? Contact us at support@plendy.app
      `.trim(),
    };

    await sgMail.send(msg);

    console.log(`Password reset email sent successfully to: ${email}`);

    return {
      success: true,
      message: "If an account exists with this email, a password reset link has been sent.",
    };
  } catch (error) {
    console.error("Error sending password reset email:", error);

    // Don't expose detailed error information to client for security
    throw new HttpsError(
      "internal",
      "Failed to send password reset email. Please try again later.",
    );
  }
});

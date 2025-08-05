# YouTube Integration Setup Guide

This guide will help you set up YouTube channel analytics tracking and video upload capabilities in your Task Manager app.

## 🚨 **IMPORTANT: Fix OAuth Client Error**

If you're seeing "Error 401: invalid_client" or "OAuth client was not found", follow these steps:

### **Step 1: Create Google Cloud Project**

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click "Select a project" at the top
3. Click "New Project"
4. Enter a project name (e.g., "Task Manager YouTube")
5. Click "Create"

### **Step 2: Enable YouTube Data API**

1. In your new project, go to "APIs & Services" > "Library"
2. Search for "YouTube Data API v3"
3. Click on "YouTube Data API v3"
4. Click "Enable"

### **Step 3: Create OAuth 2.0 Credentials**

1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth 2.0 Client IDs"
3. If prompted, configure the OAuth consent screen:
   - User Type: External
   - App name: "Task Manager YouTube Integration"
   - User support email: Your email
   - Developer contact information: Your email
   - Click "Save and Continue" through all steps
4. Back to creating credentials:
   - Application type: **Desktop application**
   - Name: "Task Manager YouTube Integration"
   - Click "Create"
5. **Download the JSON file** (click the download button)

### **Step 4: Extract Credentials**

1. Open the downloaded JSON file
2. Look for these values:
   ```json
   {
     "installed": {
       "client_id": "YOUR_CLIENT_ID.apps.googleusercontent.com",
       "client_secret": "YOUR_CLIENT_SECRET"
     }
   }
   ```

### **Step 5: Add Credentials to api_keys.txt**

The app now supports project-specific YouTube channel linking. Each project can have its own YouTube channel credentials.

**Option A: Using the helper script (recommended)**
```bash
python add_youtube_credentials.py "Your Project Name" "your_client_id" "your_client_secret"
```

**Option B: Manual method**
Add these lines to your `api_keys.txt` file:
```
Your Project Name_YouTube_Client_ID=your_client_id_here
Your Project Name_YouTube_Client_Secret=your_client_secret_here
```

**Example:**
```
My Gaming Channel_YouTube_Client_ID=123456789-abc123.apps.googleusercontent.com
My Gaming Channel_YouTube_Client_Secret=GOCSPX-your_actual_secret_here
```

**Note:** Replace "Your Project Name" with the exact name you'll use when creating the project in the app.

### **Step 6: Test the Integration**

1. Run `flutter pub get` to ensure dependencies are installed
2. Run the app: `flutter run`
3. Create a new YouTube project
4. Click "Link YouTube Channel"
5. Follow the OAuth flow in your browser

## Prerequisites

1. A Google account with a YouTube channel
2. Google Cloud Console access
3. Flutter development environment

## Step 1: Set Up Google Cloud Project

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the YouTube Data API v3:
   - Go to "APIs & Services" > "Library"
   - Search for "YouTube Data API v3"
   - Click on it and press "Enable"

## Step 2: Create OAuth 2.0 Credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth 2.0 Client IDs"
3. Choose "Desktop application" as the application type
4. Give it a name (e.g., "Task Manager YouTube Integration")
5. Click "Create"
6. Download the credentials JSON file

## Step 3: Configure the App

1. Open the downloaded credentials JSON file
2. Copy the `client_id` and `client_secret` values
3. Add them to your `api_keys.txt` file using one of these methods:

**Option A: Using the helper script (recommended)**
```bash
python add_youtube_credentials.py "Your Project Name" "your_client_id" "your_client_secret"
```

**Option B: Manual method**
Add these lines to your `api_keys.txt` file:
```
Your Project Name_YouTube_Client_ID=your_client_id_here
Your Project Name_YouTube_Client_Secret=your_client_secret_here
```

**Note:** Replace "Your Project Name" with the exact name you'll use when creating the project in the app.

## Step 4: Install Dependencies

Run the following command to install the required dependencies:
```bash
flutter pub get
```

## Step 5: Platform-Specific Setup

### Android
Add the following permissions to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
```

### iOS
Add the following to `ios/Runner/Info.plist`:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>background-processing</string>
</array>
```

### macOS
Add the following to `macos/Runner/Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

## Step 6: Using the YouTube Integration

### Creating a YouTube Project

1. **First, add your YouTube credentials to api_keys.txt:**
   ```bash
   python add_youtube_credentials.py "Your Project Name" "your_client_id" "your_client_secret"
   ```

2. Open the Task Manager app
3. Click the "+" button to create a new project
4. Select "YouTube" as the project type
5. Enter the project name (must match the name used in step 1)
6. Fill in other project details
7. Click "Link YouTube Channel" to authenticate
8. Follow the OAuth flow in your browser
9. Paste the authorization code back into the app

**Important:** Each YouTube project can be linked to a different YouTube channel. The project name must exactly match the name you used when adding credentials to api_keys.txt.

### Features Available

#### Analytics Tracking
- **Automatic Weekly Collection**: Analytics are automatically collected every week
- **Manual Refresh**: Click the refresh button to collect analytics immediately
- **Growth Trends**: View subscriber and view growth over time
- **Historical Data**: Access up to 52 weeks of analytics history

#### Video Upload
- **Direct Upload**: Upload videos directly from your device
- **Scheduled Upload**: Schedule videos for future upload
- **Privacy Settings**: Choose between private, unlisted, or public
- **Metadata Management**: Set title, description, and tags

#### Channel Management
- **Channel Info**: View channel statistics and details
- **Upload History**: Track all uploaded videos
- **Authentication Status**: Monitor connection status

## Step 7: Background Processing

The app uses WorkManager for background tasks:
- Analytics collection runs weekly automatically
- Video uploads can be scheduled for specific times
- Notifications are sent for completed tasks

## Troubleshooting

### Authentication Issues
- Ensure your Google Cloud project has the YouTube Data API enabled
- Verify your OAuth credentials are correctly configured
- Check that your redirect URI matches the one in the code
- Make sure you're using the correct client_id and client_secret

### Upload Issues
- Ensure the video file is accessible and not corrupted
- Check that you have sufficient storage space
- Verify your internet connection is stable

### Analytics Issues
- Ensure your channel has public analytics enabled
- Check that the app has proper permissions
- Verify the background service is running

## Security Notes

- OAuth tokens are stored locally on your device
- No data is sent to external servers except YouTube's API
- Credentials are encrypted in local storage
- You can revoke access at any time through Google Account settings

## API Quotas

The YouTube Data API has daily quotas:
- Default: 10,000 units per day
- Each API call consumes different amounts of quota
- Monitor usage in Google Cloud Console

## Support

If you encounter issues:
1. Check the console logs for error messages
2. Verify your Google Cloud project configuration
3. Ensure all dependencies are properly installed
4. Check platform-specific setup requirements

## Future Enhancements

Planned features:
- Video thumbnail management
- Playlist creation and management
- Advanced analytics reporting
- Bulk video operations
- Custom upload templates 

---

## Common Causes & Solutions

### 1. **Missing or Incorrect File Picker Configuration**
- Make sure you have the latest `file_picker` dependency in your `pubspec.yaml`.
- On macOS, you must add the following to your `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:
  ```xml
  <key>com.apple.security.files.user-selected.read-only</key>
  <true/>
  ```
  This allows the app to access files the user selects.

### 2. **File Picker Not Awaiting or Not Mounted**
- If the dialog closes before the file picker returns, or if the widget is not mounted, the result may be lost.
- Make sure you are awaiting the result and not calling `setState` after the widget is disposed.

### 3. **Dialog Title Parameter**
- The `dialogTitle` parameter is not supported on all platforms. Remove it for maximum compatibility.

### 4. **FileType and allowedExtensions**
- For JSON files, use:
  ```dart
  type: FileType.custom,
  allowedExtensions: ['json'],
  ```
  (You already do this, but double-check.)

### 5. **macOS App Not Signed/Not in Applications Folder**
- On macOS, unsigned apps or those not in `/Applications` may have sandboxing issues. Try moving your app to `/Applications` and running it from there.

---

## **How to Fix**

### **Update the File Picker Call**
Replace:
```dart
FilePickerResult? result = await FilePicker.platform.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['json'],
  dialogTitle: 'Select YouTube OAuth Credentials JSON File',
);
```
With:
```dart
FilePickerResult? result = await FilePicker.platform.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['json'],
);
```
**Remove the `dialogTitle` parameter.**

---

### **Check macOS Entitlements**
Add to both `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:
```xml
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```
If you want to allow writing as well:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

---

### **Rebuild the App**
After changing entitlements, run:
```sh
flutter clean
flutter pub get
flutter run
```

---

## **Summary**

- Remove `dialogTitle` from the file picker call.
- Ensure macOS entitlements allow file access.
- Rebuild the app after changes.
- Make sure you are using the latest `file_picker` package.

Would you like me to update the code to remove the `dialogTitle` parameter and remind you about the entitlements? 
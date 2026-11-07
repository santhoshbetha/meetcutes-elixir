# Meetcutes

## Setup

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Set up the database:
   ```bash
   mix ecto.setup
   ```

3. Configure environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your local configuration
   ```

4. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Environment Variables

This project uses environment variables for configuration:

### Development
- Copy `.env.example` to `.env` and update values for local development
- The app automatically loads `.env` files in development and test environments

### Production
- Set environment variables in your deployment environment/shell
- Required variables: `DATABASE_URL`, `SECRET_KEY_BASE`, `FRONTEND_URL`

**Available Variables:**
- `FRONTEND_URL`: URL of your frontend application (dev: http://localhost:3000, prod: your production URL)
- `DATABASE_URL`: PostgreSQL connection string
- `SECRET_KEY_BASE`: Phoenix secret key base
- `PHX_HOST`: Production hostname
- `PORT`: Port to run the server on
- `AWS_ACCESS_KEY_ID`: AWS/Cloudflare R2 access key
- `AWS_SECRET_ACCESS_KEY`: AWS/Cloudflare R2 secret key
- `AWS_S3_BUCKET`: S3/R2 bucket name
- `AWS_REGION`: AWS region (use 'auto' for Cloudflare R2)
- `AWS_S3_HOST`: S3/R2 endpoint host
- `AWS_S3_ASSET_HOST`: CDN/custom domain for assets

## API Endpoints

### Authentication Required

All API endpoints require authentication. Include the session cookie or use Bearer token authentication.

### Image Upload API

#### Upload Image
```
POST /api/upload
Content-Type: multipart/form-data
```

Upload an image file. The upload is processed asynchronously in the background.

**Parameters:**
- `file`: Image file (required) - Supported formats: JPEG, PNG, GIF, WebP
- `max_size`: Maximum file size in bytes (optional, default: 5MB)

**Response:**
```json
{
  "job_id": "uuid",
  "status": "queued",
  "message": "Upload queued for processing"
}
```

#### Check Upload Status
```
GET /api/jobs/:job_id
```

Check the status of an image upload job.

**Response:**
```json
{
  "job_id": "uuid",
  "status": "completed|failed|processing",
  "result": {
    "url": "https://cdn.example.com/uploads/uuid/filename.jpg",
    "filename": "filename.jpg",
    "size": 12345
  },
  "error": "error message if failed"
}
```

#### List User Images
```
GET /api/upload/images
```

Get a list of images uploaded by the authenticated user.

**Response:**
```json
{
  "images": [
    {
      "id": "uuid",
      "filename": "image.jpg",
      "url": "https://cdn.example.com/uploads/uuid/image.jpg",
      "uploaded_at": "2024-01-01T12:00:00Z",
      "size": 12345
    }
  ]
}
```

#### Get User Avatar
```
GET /api/upload/avatar
```

Get the current user's avatar image URL.

**Response:**
```json
{
  "avatar_url": "https://cdn.example.com/uploads/uuid/avatar.jpg"
}
```

#### Delete User Account
```
DELETE /api/users/settings
```

Delete the current user's account. This performs a soft delete (marks as deleted) and removes all associated images from storage. The user will be logged out after deletion.

**Response:**
```json
{
  "message": "Account deleted successfully."
}
```

### WebSocket Channels

#### Job Updates Channel
```
Channel: "job_updates:" <> job_id
```

Subscribe to real-time updates for upload job progress.

**Events:**
- `job_started`: Job processing has begun
- `job_progress`: Upload progress updates
- `job_completed`: Job finished successfully with result
- `job_failed`: Job failed with error message

## SMTP Configuration

The application uses SMTP for sending emails (registration confirmations, password resets, etc.). Configure the following environment variables:

### Gmail SMTP
```bash
export SMTP_RELAY="smtp.gmail.com"
export SMTP_USERNAME="your-email@gmail.com"
export SMTP_PASSWORD="your-app-password"  # Not your regular password!
export SMTP_PORT="587"
```

**Gmail Setup:**
1. Enable 2-factor authentication on your Google account
2. Generate an App Password: https://support.google.com/accounts/answer/185833
3. Use the App Password as `SMTP_PASSWORD`

### Other SMTP Providers

**SendGrid:**
```bash
export SMTP_RELAY="smtp.sendgrid.net"
export SMTP_USERNAME="apikey"
export SMTP_PASSWORD="your-sendgrid-api-key"
export SMTP_PORT="587"
```

**Mailgun:**
```bash
export SMTP_RELAY="smtp.mailgun.org"
export SMTP_USERNAME="your-mailgun-smtp-username"
export SMTP_PASSWORD="your-mailgun-smtp-password"
export SMTP_PORT="587"
```

**AWS SES:**
```bash
export SMTP_RELAY="email-smtp.us-east-1.amazonaws.com"
export SMTP_USERNAME="your-ses-smtp-username"
export SMTP_PASSWORD="your-ses-smtp-password"
export SMTP_PORT="587"
```

### DKIM Configuration (Optional)

DKIM helps prevent emails from going to spam. Configure it with your DNS provider:

```bash
export DKIM_S="mail"  # DKIM selector
export DKIM_D="meetcutes.us"  # Your domain
export DKIM_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----"
```

## Production Deployment

For production deployment, set these environment variables:

```bash
export DATABASE_URL="ecto://user:password@host/database"
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export FRONTEND_URL="https://meetcutes.us"
export PHX_HOST="meetcutes.us"
export PORT="4000"

# SMTP Configuration for email sending
export SMTP_RELAY="smtp.gmail.com"
export SMTP_USERNAME="your-email@gmail.com"
export SMTP_PASSWORD="your-app-password"
export SMTP_PORT="587"

# Optional: DKIM for email authentication
export DKIM_S="mail"
export DKIM_D="meetcutes.us"
export DKIM_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----"

# AWS S3 / Cloudflare R2 Configuration
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
export AWS_S3_BUCKET="your-bucket-name"
export AWS_REGION="auto"  # Use 'auto' for Cloudflare R2
export AWS_S3_HOST="your-account-id.r2.cloudflarestorage.com"
export AWS_S3_ASSET_HOST="https://cdn.meetcutes.us"
```

Then run:
```bash
mix phx.server
```

Or for releases:
```bash
mix release
PHX_SERVER=true _build/prod/rel/meetcutes/bin/meetcutes start
```

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

==============================================================================================
This Project: Uses Finch directly. This is a low-level, high-performance pooling client. It is very "explicit"—you build a request and send it.
Pleroma: Uses Tesla. Tesla is an "HTTP client builder" (a wrapper). It can use different adapters (like Finch, Hackney, or Mint) under the hood. Pleroma has its own wrapper (Pleroma.HTTP) that adds global middleware (like proxy support or user-agents) before sending the request.

Feature        Meetcutes.Tz.HTTPClient	               Pleroma's Pleroma.HTTP.Tzdata:
          
Contract	         Tz.HTTP.HTTPClient	                   Tzdata.HTTPClient
Methods	           Only needs request/2	                 Needs get/3 and head/3
Abstraction	       Direct (Finch)                   	   Wrapped (Tesla)
Complexity	       Simple, focused on hostname/path	    Complex, handles headers and options
==============================================================================================
ADd to Calendar:
import { Calendar } from "lucide-react"; // 2026 standard for icons

const AddToCalendarButton = ({ eventId }) => {
  return (
    <a
      href={`meetcutes.us{eventId}/download`}
      className="flex items-center gap-2 px-4 py-2 bg-pink-500 text-white rounded-lg hover:bg-pink-600 transition-colors"
      download // Tells the browser to handle as a file
    >
      <Calendar size={18} />
      <span>Add to Calendar</span>
      <a href={~p"/events/#{@event.id}/download"} class="btn">Add to Calendar</a>
    </a>
  );
};
=======================================================================================================
import { useState } from "react";
import { Copy, Check } from "lucide-react";

const CalendarSubscription = ({ calendarToken }) => {
  const [copied, setCopied] = useState(false);
  const feedUrl = `webcal://meetcutes.us/feeds/calendar/${calendarToken}`;

  const copyToClipboard = () => {
    navigator.clipboard.writeText(feedUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="p-4 border rounded-xl bg-gray-50">
      <h3 className="text-sm font-semibold mb-2">Sync with your Phone</h3>
      <div className="flex items-center gap-2 bg-white p-2 border rounded-md">
        <input 
          readOnly 
          value={feedUrl} 
          className="text-xs flex-1 outline-none text-gray-500"
        />
        <button onClick={copyToClipboard} className="text-pink-500">
          {copied ? <Check size={16} /> : <Copy size={16} />}
        </button>
      </div>
      <p className="mt-2 text-xs text-gray-400">
        Copy this link to subscribe in Apple or Google Calendar.
      </p>
    </div>
  );
};
Why use webcal:// instead of https://?
In the React code above, I used the webcal:// protocol for the subscription link. When a user clicks a webcal link on an iPhone or Mac, it automatically opens the Calendar app and asks: "Would you like to subscribe to this calendar?" This is much better UX than forcing them to copy-paste.
===================================================================================================npm install react-timezone-select
import React, { useState, useEffect } from 'react';
import TimezoneSelect, { type ITimezoneOption } from 'react-timezone-select';

const TimezonePicker = ({ initialTimezone, onSave }) => {
  // 2026 Tip: Detect browser timezone if no preference is saved
  const defaultTz = initialTimezone || Intl.DateTimeFormat().resolvedOptions().timeZone;
  const [selectedTimezone, setSelectedTimezone] = useState(defaultTz);

  const handleSave = () => {
    // Send the value string (e.g. "Europe/London") to your Phoenix API
    onSave(selectedTimezone.value || selectedTimezone);
  };

  return (
    <div className="space-y-4 p-4 border rounded-xl bg-white shadow-sm max-w-md">
      <label className="block text-sm font-medium text-gray-700">
        Your Local Time Zone
      </label>
      
      <TimezoneSelect
        value={selectedTimezone}
        onChange={setSelectedTimezone}
        labelStyle="original"
        className="text-sm"
      />

      <button
        onClick={handleSave}
        className="w-full py-2 bg-pink-500 text-white rounded-lg hover:bg-pink-600 transition"
      >
        Update Time Zone
      </button>
    </div>
  );
};

export default TimezonePicker;
=============================================================================================
const handleSave = async (selectedTz) => {
  const tzString = selectedTz.value || selectedTz; // Handle object or string
  
  const response = await fetch("/api/users/update_timezone", {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${userToken}` // If using token auth
    },
    body: JSON.stringify({ time_zone: tzString }),
  });

  if (response.ok) {
    alert("Timezone updated! Your calendar feeds are now synced.");
  } else {
    const data = await response.json();
    console.error("Update failed:", data.errors);
  }
};
===================================================================================
ELECTRIC:
// src/components/EventList.tsx
import { useShape } from '@electric-sql/react'

export const EventList = () => {
  // Point to your Phoenix proxy endpoint instead of the raw Electric engine
  const { data: events, isLoading } = useShape({
    url: 'http://localhost:4000/api/shapes/events', 
  })

  const { data: events } = useShape({
  url: 'http://localhost:4000/api/shapes/nearby_events',
  params: {
    // You calculate these based on user location before calling the hook
    min_lat: 40.71, max_lat: 40.75,
    min_lng: -74.01, max_lng: -73.99
  }
})

  if (isLoading) return <div>Loading events...</div>

  return (
    <ul>
      {events.map(event => (
        <li key={event.id}>{event.title} - {event.date}</li>
      ))}
    </ul>
  )
}

OR : Post-Sync Frontend Filtering (distance)

// Precise distance filtering on the local synced data
const nearbyEvents = allEvents.filter(event => {
  return calculateDistance(userLoc, event.coords) < 10 // km
})
===========================================================
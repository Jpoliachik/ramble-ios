# Custom Transcription Endpoint API

Ramble can send audio to any HTTP endpoint for transcription. This doc is the complete reference for building a compatible backend.

## Overview

Instead of using Apple Speech (on-device) or Ramble Cloud, you can point Ramble at your own transcription server. This is useful for:

- Running your own Whisper instance
- Using a different transcription provider (Deepgram, AssemblyAI, etc.)
- Processing audio through a custom pipeline before transcription
- Keeping all data on your own infrastructure

## Setup

In the Ramble app, go to **Settings > Transcription** and select **Custom Endpoint**. Enter your endpoint URL and optionally an Authorization header value.

## Request

**Method:** `POST`
**Content-Type:** `multipart/form-data`

### Headers

| Header | Description |
|--------|-------------|
| `Content-Type` | `multipart/form-data; boundary=...` |
| `Authorization` | The value configured in Settings. Omitted if left blank. |

### Body (multipart form-data)

| Field | Type | Description |
|-------|------|-------------|
| `audio` | `file` | The audio recording as AAC/M4A. Filename is `recording.m4a`, content type is `audio/m4a`. |

### Example (curl)

```bash
curl -X POST https://your-server.example.com/transcribe \
  -H "Authorization: Bearer sk-your-api-key" \
  -F "audio=@recording.m4a;type=audio/m4a"
```

## Response

### Success (200)

Return a JSON object with a `text` field containing the transcribed text:

```json
{
  "text": "The transcribed text goes here."
}
```

### Error (non-200)

Return a JSON object with an `error` field describing what went wrong:

```json
{
  "error": "Audio too short to transcribe"
}
```

Ramble displays the error message to the user and retries according to the retry policy below.

## Retries

If your endpoint returns a non-200 status or the request fails, Ramble retries up to **5 times** with exponential backoff:

| Attempt | Delay |
|---------|-------|
| 1st retry | ~5 seconds |
| 2nd retry | ~15 seconds |
| 3rd retry | ~45 seconds |
| 4th retry | ~90 seconds |
| 5th retry | ~180 seconds |

After 5 failed retries, the transcription is marked as failed. The user can manually retry from the recording detail screen.

## Audio Format

- **Codec:** AAC (MPEG-4 Audio)
- **Container:** M4A
- **Sample rate:** 16 kHz
- **Channels:** Mono
- **Content type:** `audio/m4a`

Your server should accept M4A/AAC input. If your transcription backend requires a different format (e.g., WAV, MP3), convert on your server.

## Minimal Server Example (Node.js + Express)

```js
import express from 'express';
import multer from 'multer';
import { exec } from 'child_process';
import { promisify } from 'util';

const app = express();
const upload = multer({ dest: '/tmp/uploads/' });
const execAsync = promisify(exec);

app.post('/transcribe', upload.single('audio'), async (req, res) => {
  try {
    // Verify auth
    const token = req.headers.authorization?.replace('Bearer ', '');
    if (token !== process.env.API_KEY) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // Your transcription logic here.
    // Example: call Whisper, Deepgram, AssemblyAI, etc.
    const text = await yourTranscriptionFunction(req.file.path);

    res.json({ text });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(3000);
```

## Minimal Server Example (Python + Flask)

```python
from flask import Flask, request, jsonify
import os

app = Flask(__name__)

@app.route('/transcribe', methods=['POST'])
def transcribe():
    # Verify auth
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if token != os.environ.get('API_KEY'):
        return jsonify(error='Unauthorized'), 401

    audio = request.files.get('audio')
    if not audio:
        return jsonify(error='No audio file provided'), 400

    # Save and transcribe
    path = f'/tmp/{audio.filename}'
    audio.save(path)

    # Your transcription logic here
    text = your_transcription_function(path)

    return jsonify(text=text)
```

## Tips

- **Keep it simple.** The contract is: receive audio, return text. Everything else is up to you.
- **Auth is optional.** If your server is on a private network or uses a different auth mechanism, leave the Authorization field blank in Ramble.
- **HTTP is allowed** for local/development endpoints. For production, use HTTPS.
- **The response body only needs a `text` field.** Any other fields are ignored by Ramble.
- **Timeouts.** Ramble uses the system default URLSession timeout. For very long audio files, ensure your server responds within 60 seconds or consider async processing.

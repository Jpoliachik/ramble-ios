export default {
  async fetch(request, env) {
    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const url = new URL(request.url);

    if (url.pathname === '/transcribe' && request.method === 'POST') {
      return handleTranscribe(request, env);
    }

    if (url.pathname === '/health') {
      return json({ status: 'ok' });
    }

    return json({ error: 'Not found' }, 404);
  },
};

async function handleTranscribe(request, env) {
  const deviceId = request.headers.get('X-Device-ID') || 'unknown';

  // Parse multipart form to get the audio file
  let formData;
  try {
    formData = await request.formData();
  } catch {
    return json({ error: 'Invalid multipart form data' }, 400);
  }

  const audio = formData.get('audio');
  if (!audio || !(audio instanceof File)) {
    return json({ error: 'Missing "audio" file field' }, 400);
  }

  console.log(`[transcribe] device=${deviceId} file=${audio.name} size=${audio.size} type=${audio.type}`);

  // Forward to Groq Whisper API
  const groqForm = new FormData();
  groqForm.append('file', audio, audio.name || 'recording.m4a');
  groqForm.append('model', 'whisper-large-v3');
  groqForm.append('response_format', 'json');

  let groqRes;
  try {
    groqRes = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.GROQ_API_KEY}`,
      },
      body: groqForm,
    });
  } catch (err) {
    console.error(`[transcribe] Groq request failed: ${err.message}`);
    return json({ error: 'Transcription service unavailable' }, 503);
  }

  if (!groqRes.ok) {
    const errorBody = await groqRes.text();
    console.error(`[transcribe] Groq error ${groqRes.status}: ${errorBody}`);
    return json({ error: 'Transcription failed' }, groqRes.status >= 500 ? 502 : 400);
  }

  const result = await groqRes.json();

  console.log(`[transcribe] device=${deviceId} text_length=${result.text?.length || 0}`);

  return json({ text: result.text });
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders(),
    },
  });
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Device-ID',
  };
}

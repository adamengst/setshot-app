// In-memory rate limit store — best-effort, not shared across worker instances
const rateLimitStore = new Map();
const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;

const REQUIRED_FIELDS = ['domain', 'key', 'source', 'before_value', 'after_value', 'macos_version'];
const MAX_FIELD_LENGTH = 500;
const URL_PATTERN = /https?:\/\/|ftp:\/\/|javascript:/i;
const HTML_PATTERN = /<[a-z][\s\S]*>/i;

export default {
  async fetch(request, env) {
    // 1. Reject non-POST
    if (request.method !== 'POST') {
      return new Response(null, { status: 405 });
    }

    // 2. Parse and validate JSON body
    let body;
    try {
      body = await request.json();
    } catch {
      return new Response(null, { status: 400 });
    }

    for (const field of REQUIRED_FIELDS) {
      const value = body[field];
      if (typeof value !== 'string' || value.length === 0) {
        return new Response(null, { status: 400 });
      }
      if (value.length > MAX_FIELD_LENGTH) {
        return new Response(null, { status: 400 });
      }
      if (URL_PATTERN.test(value) || HTML_PATTERN.test(value)) {
        return new Response(null, { status: 400 });
      }
    }

    // 3. Rate-limit by IP: max 5 submissions per hour
    const ip = request.headers.get('CF-Connecting-IP') ||
               request.headers.get('X-Forwarded-For') ||
               'unknown';
    const now = Date.now();

    const timestamps = (rateLimitStore.get(ip) || [])
      .filter(ts => now - ts < RATE_LIMIT_WINDOW_MS);

    if (timestamps.length >= RATE_LIMIT_MAX) {
      return new Response(null, { status: 429 });
    }

    rateLimitStore.set(ip, [...timestamps, now]);

    // 4. Format issue body as JSON code block
    const submission = {
      domain: body.domain,
      key: body.key,
      source: body.source,
      before_value: body.before_value,
      after_value: body.after_value,
      macos_version: body.macos_version,
      submitted_at: new Date().toISOString(),
      status: 'pending'
    };

    const issueTitle = `[Submission] ${body.domain} :: ${body.key}`;
    const issueBody = '```json\n' + JSON.stringify(submission, null, 2) + '\n```';

    // 5. POST to GitHub Issues API
    const [owner, repo] = env.GITHUB_REPO.split('/');
    const githubResponse = await fetch(
      `https://api.github.com/repos/${owner}/${repo}/issues`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${env.GITHUB_TOKEN}`,
          'Accept': 'application/vnd.github+json',
          'Content-Type': 'application/json',
          'User-Agent': 'SetShot-Worker/1.0',
          'X-GitHub-Api-Version': '2022-11-28'
        },
        body: JSON.stringify({
          title: issueTitle,
          body: issueBody,
          labels: ['pending']
        })
      }
    );

    // 6. Return 200 on success, 502 on GitHub API failure
    if (!githubResponse.ok) {
      return new Response(null, { status: 502 });
    }

    return new Response(null, { status: 200 });
  }
};

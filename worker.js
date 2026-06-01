// In-memory rate limit store — best-effort, not shared across worker instances
const rateLimitStore = new Map();
const RATE_LIMIT_SINGLE_MAX = 10;
const RATE_LIMIT_BATCH_MAX = 50;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const BATCH_SIZE_MAX = 50;

const REQUIRED_FIELDS = ['domain', 'key', 'source', 'before_value', 'after_value', 'macos_version'];
const IDENTIFIER_FIELDS = ['domain', 'key', 'source', 'macos_version'];
const MAX_IDENTIFIER_LENGTH = 500;
const MAX_VALUE_LENGTH = 2000;
const MAX_FEEDBACK_NOTES_LENGTH = 1000;
const VALID_FEEDBACK_CATEGORIES = new Set(['expected_change', 'likely_noise']);
const URL_PATTERN = /https?:\/\/|ftp:\/\/|javascript:/i;
const HTML_PATTERN = /<[a-z][\s\S]*>/i;

function validateItem(item) {
  for (const field of REQUIRED_FIELDS) {
    const value = item[field];
    if (typeof value !== 'string' || value.length === 0) return false;
  }
  for (const field of IDENTIFIER_FIELDS) {
    const value = item[field];
    if (value.length > MAX_IDENTIFIER_LENGTH) return false;
    if (URL_PATTERN.test(value) || HTML_PATTERN.test(value)) return false;
  }
  if (item.before_value.length > MAX_VALUE_LENGTH) return false;
  if (item.after_value.length > MAX_VALUE_LENGTH) return false;
  if (item.feedback_category !== undefined) {
    if (typeof item.feedback_category !== 'string') return false;
    if (!VALID_FEEDBACK_CATEGORIES.has(item.feedback_category)) return false;
  }
  if (item.feedback_notes !== undefined) {
    if (typeof item.feedback_notes !== 'string') return false;
    if (item.feedback_notes.length > MAX_FEEDBACK_NOTES_LENGTH) return false;
    if (URL_PATTERN.test(item.feedback_notes) || HTML_PATTERN.test(item.feedback_notes)) return false;
  }
  return true;
}

function rateKey(ip, type) {
  return `${ip}:${type}`;
}

function checkRateLimit(ip, type, max) {
  const key = rateKey(ip, type);
  const now = Date.now();
  const timestamps = (rateLimitStore.get(key) || [])
    .filter(ts => now - ts < RATE_LIMIT_WINDOW_MS);
  if (timestamps.length >= max) return false;
  rateLimitStore.set(key, [...timestamps, now]);
  return true;
}

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return new Response(null, { status: 405 });
    }

    const path = new URL(request.url).pathname;
    if (path === '/ping') {
      return new Response(null, { status: 200 });
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return new Response(null, { status: 400 });
    }

    const ip = request.headers.get('CF-Connecting-IP') ||
               request.headers.get('X-Forwarded-For') ||
               'unknown';

    const isBatch = Array.isArray(body);

    if (isBatch) {
      // Batch submission — one GitHub issue for the whole set
      if (body.length === 0 || body.length > BATCH_SIZE_MAX) {
        return new Response(null, { status: 400 });
      }
      for (const item of body) {
        if (!validateItem(item)) return new Response(null, { status: 400 });
      }
      if (!checkRateLimit(ip, 'batch', RATE_LIMIT_BATCH_MAX)) {
        return new Response(null, { status: 429 });
      }

      const now = new Date().toISOString();
      const macosVersion = body[0].macos_version;
      const domains = [...new Set(body.map(i => i.domain))].join(', ');
      const issueTitle = `[Batch Submission] ${body.length} entries — macOS ${macosVersion}`;

      const sections = body.map(item => {
        const submission = { ...item, submitted_at: now, status: 'pending' };
        return `### ${item.domain} :: ${item.key}\n\`\`\`json\n${JSON.stringify(submission, null, 2)}\n\`\`\``;
      });
      const issueBody = sections.join('\n\n');

      const githubResponse = await postIssue(env, issueTitle, issueBody);
      return githubResponse.ok ? new Response(null, { status: 200 }) : new Response(null, { status: 502 });

    } else {
      // Single submission — one GitHub issue
      if (!validateItem(body)) return new Response(null, { status: 400 });
      if (!checkRateLimit(ip, 'single', RATE_LIMIT_SINGLE_MAX)) {
        return new Response(null, { status: 429 });
      }

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
      let issueBody = '```json\n' + JSON.stringify(submission, null, 2) + '\n```';
      if (body.feedback_category || body.feedback_notes) {
        const categoryLabel = body.feedback_category === 'expected_change'
          ? 'Expected settings change'
          : body.feedback_category === 'likely_noise'
          ? 'Likely macOS noise'
          : null;
        issueBody += '\n\n## User Feedback';
        if (categoryLabel) issueBody += `\n**Category:** ${categoryLabel}`;
        if (body.feedback_notes) issueBody += `\n**Notes:** ${body.feedback_notes}`;
      }

      const githubResponse = await postIssue(env, issueTitle, issueBody);
      return githubResponse.ok ? new Response(null, { status: 200 }) : new Response(null, { status: 502 });
    }
  }
};

async function postIssue(env, title, body) {
  const [owner, repo] = env.GITHUB_REPO.split('/');
  return fetch(
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
      body: JSON.stringify({ title, body, labels: ['pending'] })
    }
  );
}

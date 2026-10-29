// In-memory rate limit store — best-effort, not shared across worker instances
const rateLimitStore = new Map();
const RATE_LIMIT_SINGLE_MAX = 10;
const RATE_LIMIT_KB_FEEDBACK_MAX = 100;
const RATE_LIMIT_BATCH_MAX = 50;
const RATE_LIMIT_SUPPORT_MAX = 5;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const BATCH_SIZE_MAX = 50;

const REQUIRED_FIELDS = ['domain', 'key', 'source', 'before_value', 'after_value', 'macos_version'];
const KB_FEEDBACK_REQUIRED_FIELDS = ['entry_id', 'domain', 'key', 'macos_version', 'issues'];
const VALID_KB_ISSUES = new Set(['no_or_incorrect_icon', 'description_needs_improvement', 'path_is_wrong', 'values_not_human_readable']);
const ISSUE_LABELS = {
  no_or_incorrect_icon: 'No or incorrect icon',
  description_needs_improvement: 'Description needs improvement',
  path_is_wrong: 'Path is wrong',
  values_not_human_readable: "Values aren't human-readable"
};
const IDENTIFIER_FIELDS = ['domain', 'key', 'source', 'macos_version'];
const MAX_IDENTIFIER_LENGTH = 500;
const MAX_VALUE_LENGTH = 2000;
const MAX_FEEDBACK_NOTES_LENGTH = 1000;
const VALID_FEEDBACK_CATEGORIES = new Set(['expected_change', 'likely_noise']);
// Links are refused because the submission queue is read and processed by an agent,
// not only by a person. A URL in a submission is an invitation to fetch
// attacker-controlled content and act on what it says. That the repository is
// private is not a reason to relax this — it is the reader, not the audience, that
// makes it a risk.
//
// This is a speed bump rather than the control: "example.com/path" with no scheme
// gets through, and tightening it to catch bare domains would reject ordinary text
// like "com.apple.dock". The real protection is that nothing here is ever treated as
// an instruction and no URL found in a submission is ever followed.
const URL_PATTERN = /https?:\/\/|ftp:\/\/|javascript:/i;
// Tag-shaped only. The previous pattern matched any "<" plus a letter followed by
// a ">" anywhere later, so an email address written as <name@example.com> was
// rejected and the sender saw only "Submission failed. Please try again."
const HTML_PATTERN = /<\/?[a-z][a-z0-9]*(\s[^<>]*)?>/i;

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

// Files served from setshot.tidbits.com, so the URLs built into the app name a host
// that can be pointed elsewhere without an update. The repositories stay the single
// source: appcast.xml is still read straight from raw.githubusercontent.com by the
// betas, which carry that URL as their feed, so it has to keep being published there.
const PROXIED_FILES = {
  '/appcast.xml': 'https://raw.githubusercontent.com/adamengst/setshot-app/main/appcast.xml',
  '/kb/version.json': 'https://raw.githubusercontent.com/adamengst/setshot-kb/main/version.json',
  '/kb/settings-kb.json': 'https://raw.githubusercontent.com/adamengst/setshot-kb/main/settings-kb.json'
};
const PROXY_CACHE_SECONDS = 300;

// Only a success is cached at the edge. Any upstream failure becomes an uncached 502,
// so a GitHub outage or a missing file never sits in the cache, or reaches the app,
// as a 200 with an error page for a body.
async function proxyFile(request, upstreamURL) {
  let upstream;
  try {
    upstream = await fetch(upstreamURL, {
      cf: {
        cacheEverything: true,
        cacheTtlByStatus: { '200-299': PROXY_CACHE_SECONDS, '300-599': 0 }
      }
    });
  } catch {
    return new Response(null, { status: 502, headers: { 'Cache-Control': 'no-store' } });
  }
  if (upstream.status !== 200) {
    return new Response(null, { status: 502, headers: { 'Cache-Control': 'no-store' } });
  }
  const headers = { 'Cache-Control': `public, max-age=${PROXY_CACHE_SECONDS}` };
  for (const name of ['Content-Type', 'ETag', 'Last-Modified']) {
    const value = upstream.headers.get(name);
    if (value) headers[name] = value;
  }
  if (request.method === 'HEAD') {
    await upstream.body?.cancel();
    return new Response(null, { status: 200, headers });
  }
  return new Response(upstream.body, { status: 200, headers });
}

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;

    if (Object.hasOwn(PROXIED_FILES, path)) {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return new Response(null, { status: 405 });
      }
      return proxyFile(request, PROXIED_FILES[path]);
    }

    if (request.method !== 'POST') {
      return new Response(null, { status: 405 });
    }

    // Submissions answer at "/submit" and, for the betas, which post to the
    // workers.dev root, at "/". Any other path used to be taken as a submission too;
    // nothing ever posted to one, so it is now refused.
    const isSubmission = path === '/' || path === '/submit';
    if (!isSubmission && path !== '/kb-feedback' && path !== '/support') {
      return new Response(null, { status: 404 });
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

    if (path === '/kb-feedback') {
      return handleKBFeedback(body, ip, env);
    }
    if (path === '/support') {
      return handleSupport(body, ip, env);
    }

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
      const appVersion = body[0].app_version ? `, SetShot ${body[0].app_version}` : '';
      const issueTitle = `[Batch Submission] ${body.length} entries — macOS ${macosVersion}${appVersion}`;

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
        app_version: body.app_version,
        kb_version: body.kb_version,
        submitted_at: new Date().toISOString(),
        status: 'pending'
      };

      const appVersion = body.app_version ? ` — SetShot ${body.app_version}` : '';
      const issueTitle = `[Submission] ${body.domain} :: ${body.key}${appVersion}`;
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

async function postIssue(env, title, body, labels = ['pending']) {
  return githubIssues(env, 'POST', '', { title, body, labels });
}

const GITHUB_HEADERS = {
  'Accept': 'application/vnd.github+json',
  'Content-Type': 'application/json',
  'User-Agent': 'SetShot-Worker/1.0',
  'X-GitHub-Api-Version': '2022-11-28'
};

async function githubIssues(env, method, suffix, payload) {
  const [owner, repo] = env.GITHUB_REPO.split('/');
  return fetch(
    `https://api.github.com/repos/${owner}/${repo}/issues${suffix}`,
    {
      method,
      headers: { ...GITHUB_HEADERS, 'Authorization': `Bearer ${await githubToken(env)}` },
      body: JSON.stringify(payload)
    }
  );
}

// Issues are filed as the SetShot Submissions GitHub App rather than with a personal
// token. GitHub never notifies anyone about their own activity, so issues filed with
// Adam's token reached no one's inbox; filed by the app, they notify everyone watching
// the repository. The app holds only Issues read/write, on this one repository.
//
// The app's credentials are its ID, its installation ID and its private key, in PKCS#8
// form — GitHub hands out PKCS#1, which Web Crypto cannot import. The worker signs a
// short-lived JWT with the key and trades it for an installation token, which lasts an
// hour and is reused until shortly before it expires. Like the rate limit store, the
// cache is per instance; a fresh instance simply asks for a token of its own.
//
// Until the app's secrets are set, GITHUB_TOKEN is used as before.
let installationToken = null;

async function githubToken(env) {
  if (!env.GITHUB_APP_ID) return env.GITHUB_TOKEN;
  if (installationToken && Date.now() < installationToken.refreshAt) return installationToken.token;

  const response = await fetch(
    `https://api.github.com/app/installations/${env.GITHUB_APP_INSTALLATION_ID}/access_tokens`,
    {
      method: 'POST',
      headers: { ...GITHUB_HEADERS, 'Authorization': `Bearer ${await appJWT(env)}` }
    }
  );
  // A failed exchange yields no token, so the issue request that follows is refused
  // and the sender sees the same 502 as any other GitHub failure.
  if (!response.ok) return '';
  const { token, expires_at } = await response.json();
  installationToken = { token, refreshAt: Date.parse(expires_at) - 5 * 60 * 1000 };
  return token;
}

async function appJWT(env) {
  const now = Math.floor(Date.now() / 1000);
  // Backdated a minute to allow for clock drift, and kept under GitHub's ten-minute limit.
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64url(JSON.stringify({ iat: now - 60, exp: now + 540, iss: env.GITHUB_APP_ID }));
  const key = await crypto.subtle.importKey(
    'pkcs8', pemToDER(env.GITHUB_APP_PRIVATE_KEY),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${base64url(signature)}`;
}

function pemToDER(pem) {
  const base64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(base64), c => c.charCodeAt(0)).buffer;
}

function base64url(input) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : new Uint8Array(input);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// Kept in step with SubmissionValidator.swift, which applies the same rules in the
// app so a rejection can be explained before anything is sent. That copy can only be
// too lenient — whatever it misses is refused here.
function validateKBFeedback(item) {
  for (const field of KB_FEEDBACK_REQUIRED_FIELDS) {
    if (typeof item[field] !== 'string' || item[field].length === 0) return false;
  }
  for (const field of ['entry_id', 'domain', 'key', 'macos_version']) {
    if (item[field].length > MAX_IDENTIFIER_LENGTH) return false;
    if (URL_PATTERN.test(item[field]) || HTML_PATTERN.test(item[field])) return false;
  }
  const issues = item.issues.split(',').map(s => s.trim()).filter(Boolean);
  if (issues.length === 0) return false;
  for (const issue of issues) {
    if (!VALID_KB_ISSUES.has(issue)) return false;
  }
  if (item.notes !== undefined) {
    if (typeof item.notes !== 'string') return false;
    if (item.notes.length > MAX_FEEDBACK_NOTES_LENGTH) return false;
    if (URL_PATTERN.test(item.notes) || HTML_PATTERN.test(item.notes)) return false;
  }
  return true;
}

async function handleKBFeedback(body, ip, env) {
  if (!validateKBFeedback(body)) return new Response(null, { status: 400 });
  if (!checkRateLimit(ip, 'kb-feedback', RATE_LIMIT_KB_FEEDBACK_MAX)) return new Response(null, { status: 429 });

  const issues = body.issues.split(',').map(s => s.trim()).filter(Boolean);
  const allIssueKeys = ['no_or_incorrect_icon', 'description_needs_improvement', 'path_is_wrong', 'values_not_human_readable'];
  const checkboxes = allIssueKeys
    .map(k => `- [${issues.includes(k) ? 'x' : ' '}] ${ISSUE_LABELS[k]}`)
    .join('\n');

  const issueTitle = `[KB Feedback] ${body.entry_id}`;
  const issueBody = `## Entry
**ID:** ${body.entry_id}
**Domain:** ${body.domain} :: ${body.key}
**Current description:** ${body.current_description || '(none)'}
**Current location:** ${body.current_ui_location || '(none)'}
**Current settings URL:** ${body.current_settings_url || '(none)'}
**Current icon bundle:** ${body.current_icon_bundle_id || '(none)'}
**macOS:** ${body.macos_version}
**SetShot:** ${body.app_version || '(not reported)'}, knowledge base ${body.kb_version || '(not reported)'}

## Issues Reported
${checkboxes}

## Notes
${body.notes || '(none)'}

## Metadata
\`\`\`json
${JSON.stringify({ ...body, submitted_at: new Date().toISOString() }, null, 2)}
\`\`\``;

  const githubResponse = await postIssue(env, issueTitle, issueBody, ['kb-feedback']);
  return githubResponse.ok ? new Response(null, { status: 200 }) : new Response(null, { status: 502 });
}

// Support requests take free text, so unlike the routes above they accept links and
// angle brackets rather than refusing them: someone asking for help will paste a
// forum link or an error message with <brackets> in it, and refusing would only
// show them "Submission failed." Instead the message is written in ordinary type with
// every character Markdown would act on escaped, so GitHub shows it as typed — no
// HTML, no formatting, no links of its making — and every "://" is rewritten so that
// nothing in it reads as a URL to an agent either. The rule from the comment at the
// top still applies: nothing here is an instruction, and no address found in a
// request is ever followed.
const SUPPORT_KINDS = {
  bug: { title: 'Bug', label: 'bug' },
  question: { title: 'Question', label: 'question' },
  suggestion: { title: 'Suggestion', label: 'enhancement' }
};
const MAX_SUPPORT_MESSAGE_LENGTH = 5000;
const MAX_NAME_LENGTH = 100;
// The name is written as "Name <address> writes:", so it may not hold angle brackets,
// line breaks or other control characters. Kept in step with SubmissionValidator.swift.
const NAME_FORBIDDEN = /[\u0000-\u001f\u007f<>]/;
const MAX_EMAIL_LENGTH = 254;
// Deliberately narrow, and kept in step with SubmissionValidator.swift. The address
// goes into a mailto: link in the issue, so anything that could end the address or
// start a query — "?", "&", "#", "%", parentheses, spaces — is refused rather than
// escaped.
const EMAIL_PATTERN = /^[A-Za-z0-9._+'-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$/;
const SUPPORT_DIAGNOSTIC_FIELDS = {
  app_version: 'SetShot',
  kb_version: 'Knowledge base',
  macos_version: 'macOS',
  mac_model: 'Mac model',
  chip: 'Chip',
  full_disk_access: 'Full Disk Access',
  media_access: 'Media & Apple Music'
};
const MAX_QUOTED_REPLY_LENGTH = 1500;

function validateSupport(item) {
  if (typeof item !== 'object' || item === null || Array.isArray(item)) return false;
  if (!Object.hasOwn(SUPPORT_KINDS, item.kind)) return false;
  if (typeof item.message !== 'string') return false;
  const message = item.message.trim();
  if (message.length === 0 || message.length > MAX_SUPPORT_MESSAGE_LENGTH) return false;
  if (item.name !== undefined) {
    if (typeof item.name !== 'string') return false;
    const name = item.name.trim();
    if (name.length === 0 || name.length > MAX_NAME_LENGTH) return false;
    if (NAME_FORBIDDEN.test(name) || URL_PATTERN.test(name)) return false;
  }
  if (item.email !== undefined) {
    if (typeof item.email !== 'string') return false;
    if (item.email.length > MAX_EMAIL_LENGTH || !EMAIL_PATTERN.test(item.email)) return false;
  }
  if (item.diagnostics !== undefined) {
    const d = item.diagnostics;
    if (typeof d !== 'object' || d === null || Array.isArray(d)) return false;
    for (const [field, value] of Object.entries(d)) {
      if (!Object.hasOwn(SUPPORT_DIAGNOSTIC_FIELDS, field)) return false;
      if (typeof value !== 'string' || value.length > MAX_IDENTIFIER_LENGTH) return false;
      if (URL_PATTERN.test(value) || HTML_PATTERN.test(value)) return false;
    }
  }
  return true;
}

function defangLinks(text) {
  return text.replace(/:\/\//g, '[:]//');
}

// Backslash-escapes what Markdown would act on, so the sender's text appears exactly as
// typed: emphasis, code, links, HTML and quotes inline, and at the start of a line the
// markers for headings, lists and rules. Indentation is cut to three spaces, since four
// would make a code block. GitHub keeps line breaks within a paragraph, so the text's
// own lines survive. The plain-text part of GitHub's notification email shows the
// source, backslashes included.
function escapeMarkdown(text) {
  return text
    .replace(/[\\`*_[\]<>~|&]/g, '\\$&')
    .replace(/^[ \t]{4,}/gm, '   ')
    .replace(/^([ \t]*)([#+=-])/gm, '$1\\$2')
    // A backslash before a digit is not an escape, so the period or parenthesis is.
    .replace(/^([ \t]*\d+)([.)])/gm, '$1\\$2');
}

function supportSummary(kind, message) {
  const firstLine = defangLinks(message.split('\n')[0].trim());
  const short = firstLine.length > 60 ? firstLine.slice(0, 59) + '…' : firstLine;
  return `${SUPPORT_KINDS[kind].title}: ${short}`;
}

// The reply link is added once the issue exists, because its subject carries the
// issue number — that is what ties the email thread back to the issue.
function replyLink(email, name, number, summary, message) {
  let quoted = message.length > MAX_QUOTED_REPLY_LENGTH
    ? message.slice(0, MAX_QUOTED_REPLY_LENGTH) + '…'
    : message;
  quoted = quoted.split('\n').map(line => `> ${line}`).join('\n');
  const subject = `SetShot support #${number}: ${summary}`;
  // Greeting, then their words, then room to answer below them.
  const greeting = name ? `Hi ${name.split(/\s+/)[0]},\n\n` : '';
  const body = `${greeting}${quoted}\n\n`;
  // encodeURIComponent leaves parentheses alone, and either one would end the
  // Markdown link early.
  const encode = s => encodeURIComponent(s).replace(/\(/g, '%28').replace(/\)/g, '%29');
  return `mailto:${email}?subject=${encode(subject)}&body=${encode(body)}`;
}

function supportIssueBody(item, message, submittedAt, number) {
  const name = item.name ? item.name.trim() : null;
  const sender = name && item.email ? `${name} <${item.email}>`
    : name || item.email || 'Anonymous';

  // Absent until the issue exists, since the link's subject carries its number.
  let reply = '';
  if (item.email && number !== null) {
    const link = replyLink(item.email, name, number, supportSummary(item.kind, message),
      defangLinks(message));
    reply = `\n\n[Reply by email](${link})`;
  } else if (!item.email) {
    reply = '\n\nNo email address given, so no reply is possible.';
  }

  // Unheaded: the labelled lines speak for themselves, and when the sender left
  // diagnostics out there is nothing to show.
  let diagnostics = '';
  if (item.diagnostics && Object.keys(item.diagnostics).length > 0) {
    diagnostics = '\n\n' + Object.entries(SUPPORT_DIAGNOSTIC_FIELDS)
      .filter(([field]) => item.diagnostics[field] !== undefined)
      .map(([field, label]) => `**${label}:** ${item.diagnostics[field]}`)
      .join('\n');
  }

  return `${escapeMarkdown(sender)} writes:

${defangLinks(escapeMarkdown(message))}${reply}${diagnostics}

**Submitted:** ${submittedAt}`;
}

async function handleSupport(body, ip, env) {
  if (!validateSupport(body)) return new Response(null, { status: 400 });
  if (!checkRateLimit(ip, 'support', RATE_LIMIT_SUPPORT_MAX)) return new Response(null, { status: 429 });

  const message = body.message.trim();
  const submittedAt = new Date().toISOString();
  const labels = ['support', SUPPORT_KINDS[body.kind].label];
  if (body.email) labels.push('needs-reply');

  const created = await postIssue(env, `[Support] ${supportSummary(body.kind, message)}`,
    supportIssueBody(body, message, submittedAt, null), labels);
  if (!created.ok) return new Response(null, { status: 502 });

  // A failure here leaves the issue without its reply link, which is worth less than
  // telling the sender their request failed when it arrived.
  if (body.email) {
    const { number } = await created.json();
    await githubIssues(env, 'PATCH', `/${number}`,
      { body: supportIssueBody(body, message, submittedAt, number) });
  }
  return new Response(null, { status: 200 });
}

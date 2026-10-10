const BASE = 'https://closeac.d-dos.cc';
const NODELOC = 'https://www.nodeloc.com';
const FLOW_COOKIE = '__Host-nekoloc-flow';
const USER_COOKIE = '__Host-nekoloc-account';
const encoder = new TextEncoder();

export function accountUrl(username) {
  if (typeof username !== 'string' || !/^[\p{L}\p{N}_][\p{L}\p{N}_.-]{0,99}$/u.test(username)) {
    throw new Error('Invalid username');
  }
  return `${NODELOC}/u/${encodeURIComponent(username)}/preferences/account`;
}

function escape(value) {
  return String(value).replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
}
function b64(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}
function unb64(value) {
  if (!/^[A-Za-z0-9_-]{1,2048}$/.test(value)) throw new Error('Invalid cookie');
  return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
}
async function key(secret) {
  const bytes = unb64(secret);
  if (bytes.length !== 32) throw new Error('Invalid session secret');
  return crypto.subtle.importKey('raw', bytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
}
export async function seal(payload, secret, purpose) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({name: 'AES-GCM', iv, additionalData: encoder.encode(purpose)},
    await key(secret), encoder.encode(JSON.stringify({...payload, exp: Date.now() + 300000})));
  return b64(new Uint8Array([...iv, ...new Uint8Array(encrypted)]));
}
export async function unseal(value, secret, purpose) {
  try {
    const bytes = unb64(value);
    const plain = await crypto.subtle.decrypt({name: 'AES-GCM', iv: bytes.slice(0, 12), additionalData: encoder.encode(purpose)},
      await key(secret), bytes.slice(12));
    const data = JSON.parse(new TextDecoder().decode(plain));
    if (!Number.isFinite(data.exp) || data.exp <= Date.now() || data.exp > Date.now() + 300000) return null;
    return data;
  } catch { return null; }
}
function cookie(name, value, age = 300) {
  return `${name}=${value}; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=${age}`;
}
function getCookie(request, name) {
  return request.headers.get('Cookie')?.split(';').map(v => v.trim()).find(v => v.startsWith(`${name}=`))?.slice(name.length + 1);
}
function headers() {
  return new Headers({'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff', 'Permissions-Policy': 'camera=(), microphone=(), geolocation=()'});
}
function redirect(path, cookies = []) {
  const h = headers(); h.set('Location', path);
  cookies.forEach(v => h.append('Set-Cookie', v));
  return new Response(null, {status: 303, headers: h});
}
const errors = {
  denied: '你取消了 NodeLoc 授权。可重新登录，或输入用户名继续。',
  state: '登录验证已失效，请重新登录。',
  login: 'NodeLoc 登录暂时失败，请重试，或输入用户名继续。',
  username: '请输入有效的 NodeLoc 用户名，不要填写昵称、邮箱或完整网址。',
  setup: '自动登录暂未启用，你仍可输入用户名前往账户设置。',
};
/** @param {{username?: string, authenticated?: boolean, configured?: boolean, error?: string|null, status?: number}} [options] */
export function page({username, authenticated = false, configured = false, error, status = 200} = {}) {
  const destination = username ? accountUrl(username) : null;
  const nonce = b64(crypto.getRandomValues(new Uint8Array(18)));
  const h = headers();
  h.set('Content-Type', 'text/html; charset=utf-8');
  h.set('Content-Security-Policy', `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'`);
  const guidance = `<section class="notice"><h2>跳转后如何申请注销</h2><p>进入 NodeLoc 账户设置后，请点击页面下方的<strong>“请求归档”</strong>，提交账户注销申请。</p><p>注销由 NodeLoc 管理员手动处理。提交请求不表示账户已立即删除，请等待管理员完成注销。</p></section>`;
  const content = destination ? `<p>${authenticated ? 'NodeLoc 已验证的用户名' : '你输入的 NodeLoc 用户名'}：<strong>${escape(username)}</strong></p>${guidance}<p role="status" aria-live="polite" id="countdown">3 秒后前往 NodeLoc 账户设置。</p><a class="button" id="destination" href="${escape(destination)}">立即前往账户设置</a><button class="secondary" id="cancel" type="button">取消自动跳转</button><p><a href="/delete-account">返回入口 / 更换账号</a></p><noscript><p>浏览器未启用 JavaScript，请点击“立即前往账户设置”。</p></noscript>`
    : `<p>此页面帮助 Nekoloc 用户前往 NodeLoc 申请账户注销。登录后会自动获取用户名，显示提示并等待 3 秒后跳转。</p>${guidance}${error ? `<p role="alert" class="error">${escape(errors[error] || errors.login)}</p>` : ''}${configured ? '<a class="button" href="/auth/nodeloc">使用 NodeLoc 登录</a>' : '<p class="muted">自动登录尚未启用，可先输入用户名继续。</p>'}<details${configured ? '' : ' open'}><summary>输入用户名继续</summary><form method="post" action="/delete-account/manual"><label for="username">NodeLoc 用户名（不是昵称）</label><input id="username" name="username" required maxlength="100" autocomplete="username" autocapitalize="none" spellcheck="false"><button class="button" type="submit">前往我的账户设置</button></form></details>`;
  const script = destination ? `<script nonce="${nonce}">const end = Date.now() + 3000; const text = document.getElementById('countdown'); const timer = setInterval(() => { const remaining = Math.max(0, Math.ceil((end - Date.now()) / 1000)); text.textContent = remaining + ' 秒后前往 NodeLoc 账户设置。'; if (remaining === 0) { clearInterval(timer); location.replace(document.getElementById('destination').href); } }, 100); document.getElementById('cancel').addEventListener('click', () => { clearInterval(timer); text.textContent = '自动跳转已取消。你可以阅读说明后手动前往。'; document.getElementById('cancel').disabled = true; });</script>` : '';
  const body = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Nekoloc · 账户注销入口</title><style nonce="${nonce}">*{box-sizing:border-box}body{margin:0;background:#fff;color:#111;font:16px/1.7 system-ui,-apple-system,sans-serif}main{max-width:680px;margin:64px auto;padding:0 24px}h1{font-size:30px;line-height:1.3}h2{font-size:18px;margin-top:0}.eyebrow,.muted,footer{color:#666}.notice{border:1px solid #ddd;padding:20px;border-radius:16px;margin:24px 0}a{color:inherit}.button{display:inline-block;background:#111;color:#fff;border:1px solid #111;border-radius:12px;padding:12px 18px;text-decoration:none;font:inherit;cursor:pointer}.secondary{display:inline-block;background:white;color:#111;border:1px solid #ccc;border-radius:12px;padding:12px 18px;margin:8px 0 8px 8px;font:inherit;cursor:pointer}button:disabled{color:#777;cursor:default}label,input{display:block}input{width:100%;border:1px solid #999;border-radius:12px;padding:12px;margin:8px 0 16px;font:inherit}details{margin:24px 0}summary{cursor:pointer}form{margin-top:18px}.error{border-left:3px solid #111;padding:12px;background:#f5f5f5}footer{font-size:13px;border-top:1px solid #ddd;margin-top:40px;padding-top:18px}@media(max-width:600px){main{margin:32px auto}.secondary{margin-left:0;width:100%}.button{width:100%;text-align:center}}</style></head><body><main><p class="eyebrow">NEKOLOC / ACCOUNT</p><h1>账户注销入口</h1>${content}<footer>Nekoloc 是 NodeLoc 的第三方客户端。账户由 NodeLoc 管理，最终注销须在 NodeLoc 完成。此入口只临时处理用户名以生成跳转链接，不代替你提交删除请求。</footer></main>${script}</body></html>`;
  return new Response(body, {status, headers: h});
}
async function readJson(response) {
  if (!response.ok || !response.body) throw new Error('Provider response failed');
  const reader = response.body.getReader(); const chunks = []; let length = 0;
  try {
    while (true) {
      const item = await reader.read(); if (item.done) break;
      length += item.value.length;
      if (length > 65536) throw new Error('Provider response too large');
      chunks.push(item.value);
    }
  } finally { await reader.cancel(); }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const data = JSON.parse(new TextDecoder().decode(bytes));
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('Invalid provider JSON');
  return data;
}
/** @param {Request} request @param {Env} env */
async function handle(request, env) {
  const url = new URL(request.url);
  const configured = Boolean(env.NODELOC_CLIENT_ID && env.NODELOC_CLIENT_SECRET && env.SESSION_SECRET);
  if (url.origin !== BASE) return new Response('Unknown host', {status: 400, headers: headers()});
  if (request.method === 'GET' && url.pathname === '/') return redirect('/delete-account');
  if (request.method === 'GET' && url.pathname === '/robots.txt') return new Response('User-agent: *\nDisallow: /\n', {headers: headers()});
  if (request.method === 'GET' && url.pathname === '/delete-account') {
    const value = getCookie(request, USER_COOKIE);
    const user = value && env.SESSION_SECRET ? await unseal(value, env.SESSION_SECRET, USER_COOKIE) : null;
    const response = user?.username ? page({username: user.username, authenticated: true}) : page({configured, error: url.searchParams.get('error')});
    if (value) response.headers.append('Set-Cookie', cookie(USER_COOKIE, '', 0));
    return response;
  }
  if (request.method === 'POST' && url.pathname === '/delete-account/manual') {
    if (request.headers.get('Origin') !== BASE || !request.headers.get('Content-Type')?.startsWith('application/x-www-form-urlencoded')) {
      return new Response('Invalid request', {status: 403, headers: headers()});
    }
    // Limit form data before decoding; usernames need at most a few hundred bytes.
    const decoder = new TextDecoder();
    const reader = request.body?.getReader(); let body = ''; let size = 0;
    if (!reader) return page({configured, error: 'username', status: 400});
    try {
      while (true) { const part = await reader.read(); if (part.done) break;
        size += part.value.length; if (size > 2048) return new Response('Request too large', {status: 413, headers: headers()});
        body += decoder.decode(part.value, {stream: true}); }
      body += decoder.decode();
    } finally { await reader.cancel(); }
    try { return page({username: new URLSearchParams(body).get('username')?.trim()}); }
    catch { return page({configured, error: 'username', status: 400}); }
  }
  if (request.method === 'GET' && url.pathname === '/auth/nodeloc') {
    if (!configured) return page({configured, error: 'setup', status: 503});
    const state = b64(crypto.getRandomValues(new Uint8Array(32)));
    const flow = await seal({state}, env.SESSION_SECRET, FLOW_COOKIE);
    const params = new URLSearchParams({response_type: 'code', client_id: env.NODELOC_CLIENT_ID,
      redirect_uri: `${BASE}/auth/nodeloc/callback`, scope: 'openid profile', state});
    return redirect(`${NODELOC}/oauth-provider/authorize?${params}`, [cookie(FLOW_COOKIE, flow)]);
  }
  if (request.method === 'GET' && url.pathname === '/auth/nodeloc/callback') {
    const clear = cookie(FLOW_COOKIE, '', 0);
    const value = getCookie(request, FLOW_COOKIE);
    const flow = configured && value ? await unseal(value, env.SESSION_SECRET, FLOW_COOKIE) : null;
    const state = url.searchParams.get('state');
    if (!flow || typeof flow.state !== 'string' || !state || state.length !== flow.state.length ||
        encoder.encode(state).reduce((diff, ch, i) => diff | (ch ^ flow.state.charCodeAt(i)), 0) !== 0) {
      return redirect('/delete-account?error=state', [clear]);
    }
    if (url.searchParams.has('error')) return redirect('/delete-account?error=denied', [clear]);
    const code = url.searchParams.get('code');
    if (!code || code.length > 2048) return redirect('/delete-account?error=login', [clear]);
    try {
      const token = await readJson(await fetch(`${NODELOC}/oauth-provider/token`, {
        method: 'POST', signal: AbortSignal.timeout(10000), redirect: 'error',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: new URLSearchParams({grant_type: 'authorization_code', code,
          redirect_uri: `${BASE}/auth/nodeloc/callback`, client_id: env.NODELOC_CLIENT_ID,
          client_secret: env.NODELOC_CLIENT_SECRET}),
      }));
      if (typeof token.access_token !== 'string' || !token.access_token || token.access_token.length > 8192) throw new Error('Invalid token');
      const info = await readJson(await fetch(`${NODELOC}/oauth-provider/userinfo`, {
        headers: {Authorization: `Bearer ${token.access_token}`}, signal: AbortSignal.timeout(10000), redirect: 'error',
      }));
      // name is a display name; sub is an ID. Neither may substitute for the username.
      accountUrl(info.preferred_username);
      const user = await seal({username: info.preferred_username}, env.SESSION_SECRET, USER_COOKIE);
      return redirect('/delete-account', [clear, cookie(USER_COOKIE, user)]);
    } catch { return redirect('/delete-account?error=login', [clear]); }
  }
  return new Response('Not found', {status: 404, headers: headers()});
}
export default {
  /** @param {Request} request @param {Env} env */
  async fetch(request, env) {
    try { return await handle(request, env); }
    catch { return page({error: 'login', status: 503}); }
  },
};

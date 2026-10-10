import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker, {accountUrl, seal, unseal} from './worker.mjs';

const base = 'https://closeac.d-dos.cc';
const env = {NODELOC_CLIENT_ID: 'test-client', NODELOC_CLIENT_SECRET: 'test-secret',
  SESSION_SECRET: Buffer.alloc(32, 7).toString('base64url')};
const req = (path, options) => new Request(base + path, options);
const namedCookie = (response, name) => response.headers.getSetCookie().find(v => v.startsWith(name + '='))?.split(';')[0];

test('public entry is accessible without login and explains manual archive deletion', async () => {
  const response = await worker.fetch(req('/delete-account'), {});
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /Nekoloc/);
  assert.match(html, /请求归档/);
  assert.match(html, /管理员手动处理/);
  assert.match(html, /name="username"/);
  assert.doesNotMatch(html, /href="\/auth\/nodeloc"/);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
});
test('username validation prevents path traversal and HTML injection', () => {
  assert.equal(accountUrl('Foo_Bar'), 'https://www.nodeloc.com/u/Foo_Bar/preferences/account');
  assert.equal(accountUrl('用户'), 'https://www.nodeloc.com/u/%E7%94%A8%E6%88%B7/preferences/account');
  for (const bad of ['..', '../admin', 'foo/bar', '<img src=x>', 'a?b', 'a#b', '', 'x'.repeat(101)]) {
    assert.throws(() => accountUrl(bad));
  }
});
test('manual fallback displays a three-second delay and cancellation', async () => {
  const response = await worker.fetch(req('/delete-account/manual', {method: 'POST',
    headers: {Origin: base, 'Content-Type': 'application/x-www-form-urlencoded'}, body: 'username=Foo_Bar'}), {});
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.match(html, /3 秒后/);
  assert.match(html, /Date.now\(\) \+ 3000/);
  assert.match(html, /取消自动跳转/);
  assert.match(html, /你输入的 NodeLoc 用户名/);
  assert.match(html, /https:\/\/www.nodeloc.com\/u\/Foo_Bar\/preferences\/account/);
});
test('manual form rejects cross-origin, invalid and oversized submissions', async () => {
  const submit = (body, origin = base) => worker.fetch(req('/delete-account/manual', {method: 'POST',
    headers: {Origin: origin, 'Content-Type': 'application/x-www-form-urlencoded'}, body}), {});
  assert.equal((await submit('username=a', 'https://other.example')).status, 403);
  assert.equal((await submit('username=../admin')).status, 400);
  assert.equal((await submit('username=' + 'x'.repeat(3000))).status, 413);
});
test('encrypted cookies cannot be forged, expired or used for another purpose', async () => {
  const value = await seal({state: 'test'}, env.SESSION_SECRET, 'flow');
  assert.equal((await unseal(value, env.SESSION_SECRET, 'flow')).state, 'test');
  assert.equal(await unseal(value, env.SESSION_SECRET, 'account'), null);
  assert.equal(await unseal(value.slice(0, 20) + 'x' + value.slice(21), env.SESSION_SECRET, 'flow'), null);
  const original = Date.now;
  try { Date.now = () => original() + 301000;
    assert.equal(await unseal(value, env.SESSION_SECRET, 'flow'), null);
  } finally { Date.now = original; }
});
test('OAuth uses official endpoints, browser-bound state and profile-only scope', async () => {
  const response = await worker.fetch(req('/auth/nodeloc'), env);
  const url = new URL(response.headers.get('Location'));
  assert.equal(url.origin + url.pathname, 'https://www.nodeloc.com/oauth-provider/authorize');
  assert.equal(url.searchParams.get('scope'), 'openid profile');
  assert.equal(url.searchParams.get('redirect_uri'), base + '/auth/nodeloc/callback');
  const cookie = response.headers.getSetCookie()[0];
  assert.match(cookie, /^__Host-nekoloc-flow=/);
  assert.match(cookie, /HttpOnly; SameSite=Lax; Max-Age=300/);
  const missing = await worker.fetch(req('/auth/nodeloc/callback?state=' + url.searchParams.get('state') + '&code=test'), env);
  assert.equal(missing.headers.get('Location'), '/delete-account?error=state');
});
test('OAuth callback gets preferred_username and redirects through a clean URL', async t => {
  const login = await worker.fetch(req('/auth/nodeloc'), env);
  const state = new URL(login.headers.get('Location')).searchParams.get('state');
  const flow = namedCookie(login, '__Host-nekoloc-flow');
  const calls = [];
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async (url, options) => {
    calls.push({url, options});
    return Response.json(calls.length === 1 ? {access_token: 'private-test-token'} :
      {sub: 'id-not-username', name: 'Display Name', preferred_username: 'ActualUser'});
  };
  const callback = await worker.fetch(req('/auth/nodeloc/callback?state=' + state + '&code=once', {headers: {Cookie: flow}}), env);
  assert.equal(callback.headers.get('Location'), '/delete-account');
  assert.equal(calls[0].url, 'https://www.nodeloc.com/oauth-provider/token');
  assert.equal(calls[0].options.body.get('client_secret'), env.NODELOC_CLIENT_SECRET);
  assert.equal(calls[1].url, 'https://www.nodeloc.com/oauth-provider/userinfo');
  const userCookie = namedCookie(callback, '__Host-nekoloc-account');
  assert.doesNotMatch(userCookie, /ActualUser|private-test-token/);
  const target = await worker.fetch(req('/delete-account', {headers: {Cookie: userCookie}}), env);
  const html = await target.text();
  assert.match(html, /NodeLoc 已验证的用户名/);
  assert.match(html, /u\/ActualUser\/preferences\/account/);
  assert.doesNotMatch(html, /private-test-token|Display Name|id-not-username/);
  assert.match(target.headers.get('Set-Cookie'), /Max-Age=0/);
});
test('mismatched OAuth state never contacts provider', async t => {
  const login = await worker.fetch(req('/auth/nodeloc'), env);
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async () => { assert.fail('Provider must not be called'); };
  const response = await worker.fetch(req('/auth/nodeloc/callback?state=wrong&code=once',
    {headers: {Cookie: namedCookie(login, '__Host-nekoloc-flow')}}), env);
  assert.equal(response.headers.get('Location'), '/delete-account?error=state');
});
test('OAuth rejects display name fallback and provider errors', async t => {
  const login = await worker.fetch(req('/auth/nodeloc'), env);
  const state = new URL(login.headers.get('Location')).searchParams.get('state');
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  let calls = 0;
  globalThis.fetch = async () => Response.json(++calls === 1 ? {access_token: 'token'} : {name: 'Display Name', sub: '123'});
  const response = await worker.fetch(req('/auth/nodeloc/callback?state=' + state + '&code=once',
    {headers: {Cookie: namedCookie(login, '__Host-nekoloc-flow')}}), env);
  assert.equal(response.headers.get('Location'), '/delete-account?error=login');
  assert.equal(namedCookie(response, '__Host-nekoloc-account'), undefined);
});

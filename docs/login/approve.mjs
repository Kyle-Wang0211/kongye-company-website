const provider = 'custom:casdoor';
const element = id => document.getElementById(id);
const button = element('approve');
const status = element('status');
let client;
let owner;
let verification;
let busy = false;

function verificationUrl(value) {
  const url = new URL(value);
  const entries = [...url.searchParams];
  if (url.origin !== location.origin || url.origin !== 'https://kongye.space' ||
      url.username || url.password || url.hash ||
      !/^\/casdoor\/login\/oauth\/device\/[A-Za-z0-9-]{4,64}$/.test(url.pathname) ||
      entries.length !== 1 || entries[0][0] !== 'cancelToken' ||
      !entries[0][1] || entries[0][1].length > 2048) {
    throw new Error('invalid-verification');
  }
  return url;
}

function signedOut() {
  button.disabled = true;
  element('sign-in').hidden = false;
  status.textContent = '请先登录你的窗后城账号，再确认本次网页登录。';
}

async function sameAccount() {
  const {data, error} = await client.auth.getUser();
  if (error || !data.user || data.user.id !== owner) throw new Error('account-changed');
  return data.user;
}

async function bridge(action) {
  await sameAccount();
  const {data, error} = await client.auth.getSession();
  if (error || data.session?.user.id !== owner) throw new Error('account-changed');
  const response = await fetch('/qr-login/' + action, {
    method: 'POST',
    credentials: 'omit',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + data.session.access_token,
    },
    body: JSON.stringify({verificationUrl: verification.href, confirmed: true}),
  });
  if (!response.ok) throw new Error('approval-failed');
  return response.json();
}

button.onclick = async () => {
  if (busy || !owner) return;
  busy = true;
  button.disabled = true;
  status.classList.remove('error');
  status.textContent = '正在确认…';
  try {
    const user = await sameAccount();
    if (!user.identities?.some(identity => identity.provider === provider)) {
      const prepared = await bridge('prepare');
      if (prepared.userId !== owner || !prepared.idToken || !prepared.accessToken) {
        throw new Error('approval-failed');
      }
      await sameAccount();
      const {data, error} = await client.auth.linkIdentity({
        provider,
        token: prepared.idToken,
        access_token: prepared.accessToken,
      });
      if (error || data.user?.id !== owner) throw new Error('approval-failed');
    }
    const approved = await bridge('approve');
    if (approved.approved !== true || approved.userId !== owner) {
      throw new Error('approval-failed');
    }
    element('cancel').textContent = '返回小程序';
    element('link-notice').hidden = true;
    button.textContent = '已确认';
    status.textContent = '已确认登录，请返回电脑。';
  } catch (error) {
    status.classList.add('error');
    status.textContent = error.message === 'account-changed'
      ? '账号状态已变化，请重新扫描并确认。'
      : '确认未完成。二维码可能已过期，请在电脑刷新二维码后重新扫描。';
    button.disabled = false;
  } finally {
    busy = false;
  }
};

async function initialize() {
  verification = verificationUrl(
    new URLSearchParams(location.hash.slice(1)).get('verification') || location.href,
  );
  element('confirmation-code').textContent = '确认码 ' + verification.pathname.split('/').pop();
  const returnTo = '/login/approve.html#verification=' + encodeURIComponent(verification.href);
  element('sign-in').href = '/login/?returnTo=' + encodeURIComponent(returnTo);
  const response = await fetch('/community-config.json', {cache: 'no-cache'});
  if (!response.ok) throw new Error('config');
  const config = await response.json();
  client = window.supabase.createClient(config.origin, config.anonKey, {
    auth: {
      storageKey: 'sb-api-rds20261104-auth-token',
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false,
    },
  });
  const {data, error} = await client.auth.getUser();
  if (error || !data.user) {
    signedOut();
    return;
  }
  owner = data.user.id;
  element('account').textContent = data.user.user_metadata?.display_name ||
      data.user.user_metadata?.nickname || '当前已登录账号';
  element('link-notice').hidden = data.user.identities?.some(identity => identity.provider === provider) ?? false;
  button.disabled = false;
  status.textContent = '点击确认后，电脑将登录当前账号。';
}

initialize().catch(() => {
  button.disabled = true;
  status.classList.add('error');
  status.textContent = '登录请求无效，请重新扫描电脑上的二维码。';
});

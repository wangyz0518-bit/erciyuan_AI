const $ = id => document.getElementById(id);
const titles = { overview: '工作概览', reports: '社区举报', feedback: '用户反馈' };
const kinds = { post: '帖子举报', comment: '评论举报', feedback: '用户反馈' };
const outcomes = { hide: '已下架', dismiss: '已驳回', reply: '已回复' };
const messages = {
  INVALID_CREDENTIALS: '用户名或密码不正确。', OPERATOR_REQUIRED: '此账户没有运营管理权限。',
  LOGIN_REQUIRED: '登录已过期，请重新登录。', TRY_LATER: '操作过于频繁，请稍后再试。',
  TICKET_ALREADY_HANDLED: '这条记录已由其他管理员处理，请刷新队列。'
};
let token = '', page = 'overview', cursor = null, revision = 0, currentTicket = null;

function el(tag, text, className) {
  const node = document.createElement(tag);
  node.textContent = text;
  if (className) node.className = className;
  return node;
}
async function api(path, method = 'GET', body = null, credential = token) {
  const headers = {};
  if (credential) headers.Authorization = 'Bearer ' + credential;
  if (body) headers['Content-Type'] = 'application/json';
  const response = await fetch(path, {
    method, headers, body: body ? JSON.stringify(body) : null, cache: 'no-store', redirect: 'error'
  });
  const data = await response.json();
  if (!response.ok) {
    const code = data.error?.code || String(response.status);
    const error = new Error(messages[code] || '请求未完成，请稍后重试。');
    if (credential && credential === token && (response.status === 401 || response.status === 403)) {
      reset(error.message);
    }
    throw error;
  }
  return data;
}
function reset(message = '') {
  revision++;
  token = '';
  currentTicket = null;
  if ($('resolution').open) $('resolution').close();
  $('workspace').hidden = true;
  $('gate').hidden = false;
  $('identity').textContent = '';
  $('tickets').replaceChildren();
  $('daily').replaceChildren();
  $('case-detail').replaceChildren();
  $('login-error').textContent = message;
  $('login').reset();
}
$('login').onsubmit = async event => {
  event.preventDefault();
  const form = event.currentTarget;
  const button = form.querySelector('button');
  button.disabled = true;
  $('login-error').textContent = '';
  let issued = '';
  try {
    const credentials = Object.fromEntries(new FormData(form));
    const session = await api('/community/login', 'POST', credentials, '');
    issued = session.token;
    const overview = await api('/ops/api/overview', 'GET', null, issued);
    token = issued;
    form.reset();
    $('identity').textContent = overview.username;
    $('gate').hidden = true;
    $('workspace').hidden = false;
    await navigate('overview');
  } catch (error) {
    if (issued) await api('/community/logout', 'POST', null, issued).catch(() => {});
    reset(error.message);
  } finally {
    button.disabled = false;
  }
};
$('logout').onclick = async () => {
  const previous = token;
  reset();
  try { await api('/community/logout', 'POST', null, previous); }
  catch { $('login-error').textContent = '已退出当前页面，服务端会话撤销失败。'; }
};
function showOverview(data) {
  $('pending-reports').textContent = data.pending.reports;
  $('pending-feedback').textContent = data.pending.feedback;
  const daily = new Map(data.usage.map(x => [x.day, x]));
  const table = document.createDocumentFragment();
  let texts = 0, voices = 0;
  for (let i = data.days - 1; i >= 0; i--) {
    const day = new Date((data.since + i * 86400) * 1000).toISOString().slice(0, 10);
    const row = daily.get(day) || { text: 0, voice: 0, total: 0 };
    const tr = document.createElement('tr');
    [day, row.text, row.voice, row.total].forEach(value => tr.append(el('td', value)));
    table.append(tr);
    texts += row.text;
    voices += row.voice;
  }
  $('daily').replaceChildren(table);
  const providerRows = document.createDocumentFragment();
  const units = { model: 'token', tts: '字符', asr: '秒' };
  const fields = Array.from(document.querySelectorAll('.provider-table th'), th => th.textContent);
  for (const item of data.providers) {
    const tr = document.createElement('tr');
    const amount = item.quantity == null ? '用量未返回' :
      Number(item.quantity.toFixed(2)) + ' ' + units[item.kind] + (item.unknown_quantity ? '（部分）' : '');
    const reasons = [item.unknown_rate ? '缺单价' : '', item.unknown_quantity ? '缺用量' : ''].filter(Boolean);
    const price = item.mode === 'mock' ? '模拟 · ¥0' : item.estimated_cny == null ?
      reasons.join('、') : '¥' + item.estimated_cny.toFixed(4);
    [`${item.mode === 'mock' ? '模拟' : '在线'} · ${item.model}`, item.calls, item.failed,
      item.interrupted + ' / ' + item.unfinished, amount, price].forEach((value, index) => {
        const cell = el('td', value);
        cell.dataset.label = fields[index];
        tr.append(cell);
      });
    providerRows.append(tr);
  }
  if (!data.providers.length) {
    const cell = el('td', '此周期暂无已记录的供应商调用。');
    cell.colSpan = 6;
    const tr = document.createElement('tr');
    tr.append(cell);
    providerRows.append(tr);
  }
  $('providers').replaceChildren(providerRows);
  $('text-total').textContent = texts;
  $('voice-total').textContent = voices;
}
function caseDetails(ticket) {
  const box = document.createDocumentFragment();
  box.append(el('p', ticket.message));
  if (ticket.evidence) {
    const source = ticket.evidence;
    const lines = [source.username + ' 发布的内容', source.body];
    if (source.card) lines.push(source.card.name, source.card.description, source.card.persona);
    box.append(el('div', lines.join('\n'), 'evidence'));
  }
  return box;
}
function showTicket(ticket) {
  const card = el('article', '', 'ticket');
  const head = el('div', '', 'ticket-head');
  head.append(el('h3', '#' + ticket.id + '  ' + kinds[ticket.kind]),
    el('span', outcomes[ticket.action] || '待处理', ticket.action ? 'badge resolved' : 'badge'));
  card.append(head, el('div', ticket.reporter + ' · ' +
    new Date(ticket.created * 1000).toLocaleString('zh-CN'), 'meta'), caseDetails(ticket));
  if (ticket.action) {
    card.append(el('p', ticket.handler + ' · ' + ticket.reply));
  } else {
    const foot = el('div', '', 'ticket-foot');
    const button = el('button', ticket.kind === 'feedback' ? '回复反馈' : '处理举报');
    button.onclick = () => openResolution(ticket);
    foot.append(button);
    card.append(foot);
  }
  $('tickets').append(card);
}
async function load(append = false) {
  const version = ++revision;
  $('notice').textContent = '正在读取…';
  $('more').disabled = true;
  if (!append && page !== 'overview') {
    cursor = null;
    $('tickets').replaceChildren();
    $('more').hidden = true;
  }
  try {
    if (page === 'overview') {
      const data = await api('/ops/api/overview?days=' + $('days').value);
      if (version !== revision) return;
      showOverview(data);
    } else {
      const params = new URLSearchParams({ queue: page, status: $('status').value });
      if (append && cursor) params.set('before', cursor);
      const data = await api('/ops/api/tickets?' + params);
      if (version !== revision) return;
      data.items.forEach(showTicket);
      if (!append && !data.items.length) $('tickets').append(el('p', '当前队列没有记录。', 'empty'));
      cursor = data.next_before;
      $('more').hidden = !cursor;
    }
    $('notice').textContent = '';
  } catch (error) {
    if (version === revision) $('notice').textContent = error.message;
  } finally {
    if (version === revision) $('more').disabled = false;
  }
}
async function navigate(next) {
  page = next;
  $('page-title').textContent = titles[page];
  document.querySelectorAll('[data-page]').forEach(button => {
    if (button.dataset.page === page) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  });
  $('overview').hidden = page !== 'overview';
  $('queue').hidden = page === 'overview';
  $('status').value = 'open';
  await load();
}
document.querySelectorAll('[data-page],[data-open]').forEach(button => {
  button.onclick = () => navigate(button.dataset.page || button.dataset.open);
});
$('days').onchange = $('status').onchange = $('refresh').onclick = () => load();
$('more').onclick = () => load(true);

function openResolution(ticket) {
  currentTicket = ticket;
  const feedback = ticket.kind === 'feedback';
  $('resolve-title').textContent = (feedback ? '回复反馈 #' : '处理举报 #') + ticket.id;
  $('case-detail').replaceChildren(caseDetails(ticket));
  $('action').replaceChildren(...(feedback ? [['回复', 'reply']] :
    [['驳回举报', 'dismiss'], ['下架内容', 'hide']]).map(([label, value]) => new Option(label, value)));
  $('action-label').hidden = feedback;
  $('reply').value = '';
  $('resolve-error').textContent = '';
  $('resolution').showModal();
}
$('cancel').onclick = () => $('resolution').close();
$('resolve').onsubmit = async event => {
  event.preventDefault();
  const message = $('reply').value.trim();
  if (!message) { $('resolve-error').textContent = '请填写给提交人的回复。'; return; }
  const ticket = currentTicket, button = event.currentTarget.querySelector('[type=submit]');
  button.disabled = true;
  try {
    await api('/ops/api/tickets/' + ticket.id + '/resolve', 'POST', { action: $('action').value, message });
    $('resolution').close();
    await load();
  } catch (error) {
    $('resolve-error').textContent = error.message;
  } finally { button.disabled = false; }
};

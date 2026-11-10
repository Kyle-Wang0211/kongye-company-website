import {
  accountClientReady,
  getAccountClient,
} from './community-account.mjs?v=account-restore-20261109-v2';
import {
  ActivityEditor,
  safeActivityUrl,
  validateActivityContent,
} from './community-activities.mjs?v=activities-20261110';
const form = document.querySelector('#activity-form');
const fields = document.querySelector('#activity-fields');
const detailFields = document.querySelector('#activity-detail-fields');
const status = document.querySelector('#activity-status');
const list = document.querySelector('#activity-list');
const newButton = document.querySelector('#activity-new');
const coverPreview = document.querySelector('#activity-cover-preview');
let editor,
  rows = [],
  current = null,
  detail = {},
  busy = false,
  dirty = false,
  viewEpoch = 0,
  authorized = false;
const input = (name) => form.elements.namedItem(name);
function message(text) {
  status.textContent = text;
}
function editorField(label, value, set, { url = false } = {}) {
  const wrapper = document.createElement('label');
  wrapper.append(document.createTextNode(label));
  const control = document.createElement(url ? 'input' : 'textarea');
  control.value = value || '';
  if (url) {
    control.type = 'url';
  }
  control.addEventListener('input', () => {
    set(control.value);
    dirty = true;
  });
  wrapper.append(control);
  detailFields.append(wrapper);
}
function renderDetail() {
  detailFields.replaceChildren();
  editorField('活动简介', detail.summary, (value) => {
    detail.summary = value;
  });
  if (Array.isArray(detail.textBlocks)) {
    detail.textBlocks.forEach((text, index) =>
      editorField(
        '文字 ' + (index + 1) + ' · ' + text.trim().slice(0, 28),
        text,
        (value) => {
          detail.textBlocks[index] = value;
        },
      )
    );
  }
  if (Array.isArray(detail.sections)) {
    detail.sections.forEach((section, index) => {
      editorField('段落 ' + (index + 1) + ' 标题', section.heading, (value) => {
        section.heading = value;
      });
      editorField('段落 ' + (index + 1) + ' 正文', section.body, (value) => {
        section.body = value;
      });
    });
  }
  for (const [index, attribute] of (detail.attributes || []).entries()) {
    if (attribute.tag === 'img') {
      editorField('详情图片 ' + (index + 1) + ' 地址', attribute.src, (value) => {
        attribute.src = value;
      }, { url: true });
      editorField('详情图片 ' + (index + 1) + ' 说明', attribute.alt, (value) => {
        attribute.alt = value;
      });
    } else {editorField('详情链接 ' + (index + 1), attribute.href, (value) => {
        attribute.href = value;
      }, { url: true });}
  }
  if (detail.resortConfig) {
    editorField('三维场景地址', detail.resortConfig.sourceUrl, (value) => {
      detail.resortConfig.sourceUrl = value;
    }, { url: true });
    for (const key of ['sourceLabel', 'sourceCredit', 'sourceLicense']) {
      editorField(
        ({
          sourceLabel: '场景名称',
          sourceCredit: '资料署名',
          sourceLicense: '资料许可',
        })[key],
        detail.resortConfig[key],
        (value) => {
          detail.resortConfig[key] = value;
        },
      );
    }
    for (const point of detail.resortConfig.points || []) {
      editorField('导览点 · ' + point.title + ' · 名称', point.title, (value) => {
        point.title = value;
      });
      editorField('导览点 · ' + point.title + ' · 介绍', point.description, (value) => {
        point.description = value;
      });
    }
  }
  document.querySelector('#activity-add-section').hidden = !Array.isArray(
    detail.sections,
  );
}
function show(row) {
  current = row;
  viewEpoch++;
  dirty = false;
  const content = row?.draft ||
    {
      title: '',
      cover_url: '',
      sort_order: rows.length,
      template_key: 'article',
      detail: { summary: '', sections: [{ heading: '', body: '' }] },
    };
  detail = structuredClone(content.detail);
  input('slug').value = row?.slug || '';
  input('slug').readOnly = !!row;
  for (const key of ['title', 'cover', 'sort_order', 'template_key']) {
    input(key).value = content[key === 'cover' ? 'cover_url' : key];
  }
  input('template_key').disabled = true;
  form.hidden = false;
  renderDetail();
  updateCover();
  document.querySelector('#activity-publish').disabled = !row;
  document.querySelector('#activity-withdraw').disabled = !row?.published;
  [...list.children].forEach((button) =>
    button.setAttribute('aria-current', String(button.dataset.id === row?.id))
  );
}
function updateCover() {
  try {
    coverPreview.src = safeActivityUrl(input('cover').value);
    coverPreview.hidden = false;
  } catch {
    coverPreview.removeAttribute('src');
    coverPreview.hidden = true;
  }
}
function content() {
  for (const attribute of detail.attributes || []) {
    if (attribute.src) {
      safeActivityUrl(attribute.src);
    }
    if (attribute.href) {
      safeActivityUrl(attribute.href, { external: true });
    }
  }
  if (detail.resortConfig) {
    safeActivityUrl(detail.resortConfig.sourceUrl);
  }
  return validateActivityContent({
    title: input('title').value,
    cover_url: input('cover').value,
    sort_order: Number(input('sort_order').value),
    template_key: input('template_key').value,
    detail: structuredClone(detail),
  });
}
function renderList() {
  list.replaceChildren();
  for (const row of rows) {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.id = row.id;
    button.textContent = row.draft.title + (row.published ? ' · 已发布' : ' · 草稿');
    button.addEventListener('click', () => {
      if (busy) {
        return;
      }
      if (dirty && !confirm('放弃当前未保存的修改并打开其他活动？')) {
        return;
      }
      show(row);
    });
    list.append(button);
  }
}
async function run(operation) {
  if (busy) {
    return;
  }
  busy = true;
  fields.disabled = true;
  newButton.disabled = true;
  try {
    await operation();
  } catch (error) {
    message('操作未完成。' + (error?.message || '请重新加载后重试。'));
  } finally {
    busy = false;
    fields.disabled = false;
    newButton.disabled = !authorized;
  }
}
async function reload() {
  if (dirty && !confirm('刷新将放弃未保存的修改，继续？')) {
    return;
  }
  await run(async () => {
    authorized = false;
    rows = [];
    current = null;
    dirty = false;
    form.hidden = true;
    list.replaceChildren();
    const epoch = viewEpoch;
    const data = await editor.manage('list');
    if (epoch !== viewEpoch) {
      return;
    }
    if (!Array.isArray(data)) {
      throw Error('活动列表无效');
    }
    authorized = true;
    rows = data;
    renderList();
    form.hidden = true;
    current = null;
    dirty = false;
    message(rows.length ? '已加载活动。' : '暂无活动，可以新建。');
  });
}
form.addEventListener('input', () => {
  dirty = true;
});
input('cover').addEventListener('input', updateCover);
form.addEventListener('submit', (event) => {
  event.preventDefault();
  if (!form.reportValidity()) {
    return;
  }
  void run(async () => {
    const saved = await editor.manage('save', current, content(), input('slug').value);
    if (!saved || !saved.id) {
      throw Error('保存结果无效，请刷新确认');
    }
    rows = rows.filter((row) => row.id !== saved.id);
    rows.push(saved);
    renderList();
    show(saved);
    message('草稿已保存，公开内容保持上次发布版本。');
  });
});
newButton.addEventListener('click', () => {
  if (!dirty || confirm('放弃未保存的修改并新建活动？')) {
    show(null);
  }
});
document.querySelector('#activity-reload').addEventListener(
  'click',
  () => void reload(),
);
document.querySelector('#activity-add-section').addEventListener('click', () => {
  detail.sections.push({ heading: '', body: '' });
  dirty = true;
  renderDetail();
});
document.querySelector('#activity-preview').addEventListener('click', () => {
  try {
    const token = crypto.randomUUID();
    sessionStorage.setItem('pw-activity-preview-' + token, JSON.stringify(content()));
    window.open('screen.html?preview=' + token, '_blank');
    message('已打开当前内容预览。');
  } catch (error) {
    message(error.message);
  }
});
for (const action of ['publish', 'withdraw']) {
  document.querySelector('#activity-' + action).addEventListener('click', () => {
    if (!current) {
      return;
    }
    if (dirty) {
      message('请先保存草稿，再发布或下线。');
      return;
    }
    if (
      !confirm(
        action === 'publish'
          ? '发布此活动的完整已保存草稿？'
          : '下线此活动并从公开社区移除？',
      )
    ) return;
    void run(async () => {
      const saved = await editor.manage(action, current);
      if (!saved?.id) {
        throw Error('操作结果无效，请刷新确认');
      }
      rows = rows.map((row) => row.id === saved.id ? saved : row);
      renderList();
      show(saved);
      message(action === 'publish' ? '活动已发布。' : '活动已下线，草稿仍可继续编辑。');
    });
  });
}
document.querySelector('#activity-cover-file').addEventListener('change', (event) => {
  const file = event.target.files[0];
  if (!file) {
    return;
  }
  void run(async () => {
    input('cover').value = await editor.upload(file);
    dirty = true;
    updateCover();
    message('封面已上传，请保存草稿。');
  });
});
try {
  const client = await accountClientReady.catch(() => getAccountClient());
  editor = new ActivityEditor(client);
  const initial = await client.auth.getSession();
  let owner = initial.data?.session?.user?.id;
  client.auth.onAuthStateChange((event, session) => {
    if (event !== 'SIGNED_OUT' && session?.user?.id === owner) {
      return;
    }
    owner = session?.user?.id;
    authorized = false;
    editor.invalidate();
    viewEpoch++;
    rows = [];
    current = null;
    dirty = false;
    form.hidden = true;
    list.replaceChildren();
    newButton.disabled = true;
    message('账号状态已变化，请刷新检查管理权限。');
  });
  await reload();
} catch {
  message('请通过现有邮箱或手机号登录，并使用已授权的活动管理账号。');
}

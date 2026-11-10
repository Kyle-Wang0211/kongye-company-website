import {bindActivityDetail} from './community-activities.mjs?v=activities-20261110';
const registrationIcon = '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M8 3v4m8-4v4M4 10h16M6 5h12a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z"/><path d="m9 15 2 2 4-4"/></svg>';
const arrow = '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M5 12h14m-6-6 6 6-6 6"/></svg>';

export function mountCeramicEvent(detail = null) {
  const main = document.querySelector('main');
  const header = document.querySelector('header');
  if (!main || !header || main.dataset.ceramicEvent === 'mounted') return;
  main.dataset.ceramicEvent = 'mounted';
  main.className = 'event-page wrap';
  document.body.classList.add('event-body');
  header.classList.add('event-header');
  document.title = '瓷影｜器物与日常 · 窗后城';
  main.innerHTML = `
    <section class="event-opening" aria-labelledby="event-title">
      <div class="event-edition"><span>窗后城 · 城市会客厅</span><span>01 / 深圳 · 十一月</span></div>
      <figure class="event-cover"><img src="assets/events/porcelain-ink.png" alt="水墨山色与瓷器交织的活动封面" fetchpriority="high"><figcaption>一器一世界，一城一相逢。</figcaption></figure>
      <div class="event-intro">
        <div><p class="event-kicker">器物、手作，与生活的另一种尺度</p><h1 id="event-title">瓷影<span>器物与日常</span></h1><p class="event-lead">把目光放慢，重新看见一件器物。<br>从釉色与纹样出发，让久远的手艺，回到当下的生活。</p></div>
        <div class="event-information"><p class="event-status">活动策划预览 · 尚未开放正式报名</p><dl><div><dt>拟定日期</dt><dd><time datetime="2026-11-15">2026 年 11 月 15 日 · 周日</time></dd></div><div><dt>拟定时段</dt><dd>14:00 — 16:30</dd></div><div><dt>相见地点</dt><dd>深圳 · 南山<br><small>具体空间待公布</small></dd></div></dl><button class="event-text-button" type="button" data-event-register>留下报名意向 ${arrow}</button><p class="event-fine">时间、场地与嘉宾均待确认，最终安排以正式通知为准。</p></div>
      </div>
    </section>
    <section class="event-section event-story" aria-labelledby="event-story-title"><div class="event-section-index">01 / 关于这次相聚</div><div class="event-story-copy"><h2 id="event-story-title">泥与火之间，<br>也有我们的日常。</h2><div><p>一只碗盛过怎样的生活，一抹青花又经过多少次凝望？瓷器的故事，不只留在展柜里，也藏在我们使用、触摸和珍惜器物的每一天。</p><p>这是一场正在筹划的小型线下相聚。我们想邀您一起看器、聊器，也通过窗后城的三维作品，换一个角度，走近器物的形与神。</p></div></div></section>
    <section class="event-section" aria-labelledby="event-objects-title"><div class="event-section-heading"><div><div class="event-section-index">02 / 先从两件器物开始</div><h2 id="event-objects-title">在指尖，转一转时光。</h2></div><p>点击器物，进入社区查看三维作品</p></div><div class="event-object-grid">
      <a class="event-object" href="community/?work=c1225d92-3375-4026-8fff-94db0b9400b3&amp;release=streaming-profiles-20261103-v14"><div class="event-object-image"><span class="event-object-number">器物 01</span><img src="assets/models/cma-vase-1963-514-1346d3e18404.png" alt="彩瓷花瓶三维作品封面" loading="lazy"><span class="event-object-open">${arrow}</span></div><div class="event-object-caption"><h3>彩瓷花瓶</h3><span>看釉色，也看器形</span></div></a>
      <a class="event-object" href="community/?work=e444a429-8537-4f2b-87f6-1bbc9b62d2c1&amp;release=streaming-profiles-20261103-v14"><div class="event-object-image"><span class="event-object-number">器物 02</span><img src="assets/models/cma-dragon-jar-1986-85-9abcec526827.png" alt="青花龙纹罐三维作品封面" loading="lazy"><span class="event-object-open">${arrow}</span></div><div class="event-object-caption"><h3>青花龙纹罐</h3><span>沿着纹样，发现细节</span></div></a>
    </div><p class="event-fine event-object-note">此处为社区数字作品导览，不代表原件参展或馆方合作。</p></section>
    <section class="event-section event-guest" aria-labelledby="event-guest-title"><div class="event-section-index">03 / 与谁一起看见</div><div class="event-guest-content"><div class="event-guest-monogram" aria-hidden="true">观<span>器 · 见人</span></div><div><p class="event-kicker">策划中的对谈嘉宾</p><h2 id="event-guest-title">林观澜 <small>拟定角色名</small></h2><p>围绕陶瓷之美、器物观察与日常使用，策划一场轻松的分享与对谈。一起谈谈，一件器物如何从材料、形制，走进生活。</p><p class="event-fine">此姓名为活动策划预览用的拟定角色名，非已确认艺术家。真实嘉宾及履历将在确认后公布。</p></div></div><aside id="artist-reference-section" class="event-artist-reference" aria-labelledby="event-reference-title"><figure class="event-reference-photo"><img src="assets/events/edmund-de-waal.jpg" alt="Edmund de Waal 与其陶瓷空间装置作品，2013 年资料照片" loading="lazy"><figcaption>Rob McKeever / <a href="https://creativecommons.org/licenses/by-sa/4.0/" target="_blank" rel="noopener noreferrer">CC BY-SA 4.0</a> · 2013<br><a href="https://commons.wikimedia.org/wiki/File:Edmund_de_Waal_with_his_installation,_breathturn_(2013),_at_Gagosian,_New_York.jpg" target="_blank" rel="noopener noreferrer">Wikimedia Commons 原始资料图 ↗</a></figcaption></figure><div><p class="event-kicker">延伸观看 · 艺术参照</p><h3 id="event-reference-title">Edmund de Waal<br><span>陶瓷与空间</span></h3><p>从一件器物到一处空间，试着观察排列、间距与光线，如何改变我们观看陶瓷的方式。</p><p class="event-fine">艺术家资料图，非本次活动嘉宾。本模块仅作艺术参照，不代表艺术家参与、授权活动或合作背书。</p></div></aside></section>
    <section class="event-section" aria-labelledby="event-program-title"><div class="event-section-heading"><div><div class="event-section-index">04 / 一个下午的留白</div><h2 id="event-program-title">相聚，不必匆忙。</h2></div><p>拟定流程 · 以正式通知为准</p></div><ol class="event-program"><li><time>14:00</time><div><h3>入席 · 以茶相见</h3><p>轻松认识彼此，聊聊与您相伴的器物。</p></div><span>01</span></li><li><time>14:20</time><div><h3>观器 · 形与釉的对话</h3><p>从器形、色泽与纹样，练习细看一件瓷器。</p></div><span>02</span></li><li><time>15:10</time><div><h3>游器 · 三维里的另一面</h3><p>通过社区数字作品，自由旋转、靠近与观察。</p></div><span>03</span></li><li><time>15:50</time><div><h3>闲谈 · 把美带回日常</h3><p>开放交流，留下一段关于器物与生活的对话。</p></div><span>04</span></li></ol><p class="event-program-end">16:30 散席 · 期待下一次相遇</p></section>
    <section class="event-section event-partners" aria-labelledby="event-partners-title"><div class="event-section-index">05 / 让相聚发生</div><h2 id="event-partners-title">联合出品 · 策划席位</h2><p class="event-fine">窗后城发起；其余名称仅为视觉占位，不代表已确认合作或品牌背书。</p><div class="event-partner-grid"><div class="event-partner"><div class="event-partner-mark event-partner-brand"><img src="assets/app-icon.png" width="34" height="34" alt="">窗后城</div><span>活动发起</span></div><div class="event-partner"><div class="event-partner-mark event-mark-seal">观器</div><span>拟邀占位 · 未确认</span></div><div class="event-partner"><div class="event-partner-mark event-mark-serif">青白</div><span>拟邀占位 · 未确认</span></div><div class="event-partner"><div class="event-partner-mark event-mark-spaced">南山</div><span>拟邀占位 · 未确认</span></div></div></section>
    <div class="event-closing"><p>在城市里，为器物留一个下午。</p><button class="event-text-button" type="button" data-event-register>留下报名意向 ${arrow}</button><span>深圳 · 2026 秋</span></div>
    <dialog class="event-dialog" aria-labelledby="event-dialog-title" aria-describedby="event-dialog-description"><button class="event-dialog-close" type="button" aria-label="关闭报名意向窗口">×</button><p class="event-kicker">期待与您相见</p><h2 id="event-dialog-title">留下报名意向</h2><p id="event-dialog-description">活动尚在筹划。填写后点击下方按钮将打开您的邮箱，由您确认并发送邮件；本页面不提交或保存个人资料，也不会生成报名成功记录。</p><form class="event-form"><label>怎么称呼您 <span>选填</span><input name="name" autocomplete="name" maxlength="80" placeholder="您的名字"></label><label>意向人数<select name="people"><option value="1">1 位</option><option value="2">2 位</option><option value="3">3 位</option><option value="4">4 位</option></select></label><label>联系邮箱 <span>选填</span><input name="email" type="email" autocomplete="email" maxlength="254" placeholder="方便后续联系的邮箱"></label><p class="event-fine">意向接收：kaidong@kongye.space<br>发送邮件不等于报名确认，具体安排将另行沟通。若未配置邮箱应用，可自行发送至以上地址。</p><a class="event-send" href="mailto:kaidong@kongye.space">打开邮箱发送意向 ${arrow}</a><p class="event-mail-status" role="status"></p></form></dialog>`;
  if (detail) bindActivityDetail(main, detail, 'ceramic-20261110-v1');
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'event-header-register';
  button.setAttribute('aria-label', '留下活动报名意向');
  button.title = '留下报名意向';
  button.innerHTML = registrationIcon;
  header.append(button);
  const dialog = main.querySelector('.event-dialog');
  const form = main.querySelector('.event-form');
  const send = main.querySelector('.event-send');
  const status = main.querySelector('.event-mail-status');
  function updateMail() {
    const values = new FormData(form);
    const name = String(values.get('name') || '').trim();
    const email = String(values.get('email') || '').trim();
    const body = ['您好，我想了解「瓷影｜器物与日常」活动。', '', `称呼：${name || '未填写'}`, `意向人数：${values.get('people')} 位`, `联系邮箱：${email || '请回复本邮件'}`, '', '已知这是活动策划预览，时间、场地及嘉宾待确认；本邮件仅表达参与意向。'].join('\n');
    send.href = `mailto:kaidong@kongye.space?subject=${encodeURIComponent('瓷影｜器物与日常 · 报名意向')}&body=${encodeURIComponent(body)}`;
  }
  function openDialog() { updateMail(); status.textContent = ''; if (!dialog.open) dialog.showModal(); }
  button.addEventListener('click', openDialog);
  main.querySelectorAll('[data-event-register]').forEach(control => control.addEventListener('click', openDialog));
  main.querySelector('.event-dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => { if (event.target === dialog) { const r = dialog.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) dialog.close(); } });
  form.addEventListener('input', updateMail);
  form.addEventListener('change', updateMail);
  form.addEventListener('submit', event => event.preventDefault());
  send.addEventListener('click', event => { if (!form.reportValidity()) { event.preventDefault(); return; } updateMail(); status.textContent = '正在请求打开邮箱。请在邮箱中确认并发送；本站未提交报名。'; });
  updateMail();
}

export const resortCategories = Object.freeze([
  {id:'all',label:'全部空间'},
  {id:'rooms',label:'客房'},
  {id:'reception',label:'前台'},
  {id:'dining',label:'餐饮'},
  {id:'leisure',label:'娱乐'},
]);

// Each localPosition is XYZ in the selected cloud's render frame.
// A source-coordinate point must subtract cloud.renderOrigin before publication.
export const resortConfig = Object.freeze({
  sourceUrl:'',
  sourceLabel:'山庄空间点云',
  sourceCredit:'',
  sourceLicense:'',
  sourcePage:'',
  initialCamera:null,
  points:[],
});

export function validateResortConfig(config) {
  if (typeof config.sourceUrl !== 'string' || /^(?!https:\/\/)[a-z][a-z\d+.-]*:|^\/\//i.test(config.sourceUrl)) {
    throw new Error('点云地址需要使用 HTTPS 或站内路径');
  }
  if (!Array.isArray(config.points)) throw new Error('导览点位需要使用列表');
  const ids = new Set();
  const categories = new Set(resortCategories.slice(1).map(category=>category.id));
  for (const point of config.points) {
    if (!point.id || ids.has(point.id) || !categories.has(point.category)) throw new Error('导览点位标识或分类无效');
    if (typeof point.title !== 'string' || typeof point.description !== 'string') throw new Error('导览点位需要名称和说明');
    if (!point.localPosition || !['x','y','z'].every(axis=>Number.isFinite(point.localPosition[axis]))) throw new Error('导览点位需要模型中的三维坐标');
    ids.add(point.id);
  }
  return config;
}

export function buildResortViewerUrl(config, baseUrl) {
  validateResortConfig(config);
  const url = new URL('./pointcloud-viewer/',baseUrl);
  url.searchParams.set('source',new URL(config.sourceUrl,baseUrl).href);
  return url.href;
}

export function bindResortAnnotations(viewer, points, onSelect) {
  const annotations = points.map(point=>({
    id:point.id,
    type:'info',
    title:point.title,
    note:point.description,
    localPosition:{...point.localPosition},
    createdAt:1793923200000,
    updatedAt:1793923200000,
    ...(point.cameraState ? {cameraState:point.cameraState} : {}),
  }));
  viewer.annotate.loadAnnotations(annotations);
  viewer.annotate.setOnSelect(id=>{
    const point = points.find(candidate=>candidate.id===id);
    if (point) onSelect(point);
  });
  return viewer.annotateElements.overlay;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g,character=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));
}

// The SVG and its camera projection belong to the bundled viewer.
// These styles only make its existing annotation surface visible and operable.
const annotationStyle = `
.olv-anno-svg{position:absolute;inset:0;width:100%;height:100%;overflow:hidden;pointer-events:none}
.olv-anno-marker{pointer-events:auto;cursor:pointer;outline:none}
.olv-anno-halo{fill:#172c36b3;stroke:#ffffff80;stroke-width:1}
.olv-anno-disc{fill:#e8f5ef;stroke:#183a36;stroke-width:1}
.olv-anno-num{font:700 12px system-ui;fill:#183a36}
.olv-anno-marker:hover .olv-anno-halo,.olv-anno-marker:focus .olv-anno-halo,.olv-anno-selected .olv-anno-halo{stroke:#fff;stroke-width:3}
`;

export function mountCommunityResort(config = resortConfig) {
  validateResortConfig(config);
  const main = document.querySelector('main');
  const header = document.querySelector('header');
  if (!main || !header || main.dataset.communityResort === 'mounted') return;
  main.dataset.communityResort = 'mounted';
  main.className = 'resort-page wrap';
  document.body.classList.add('resort-body');
  header.classList.add('resort-header');
  const back = header.querySelector('.community-screen-back span');
  if (back) { delete back.dataset.i18n; back.textContent = '返回首页'; }
  document.title = '云栖山庄 · 三维度假导览 · 窗后城';
  const stylesheet = document.createElement('link');
  stylesheet.rel = 'stylesheet';
  stylesheet.href = new URL('./community-resort.css?v=resort-guide-20261106',import.meta.url).href;
  document.head.append(stylesheet);
  main.innerHTML = `
    <section class="resort-opening" aria-labelledby="resort-title">
      <div class="resort-edition"><span>窗后城 × 云栖山庄</span><span>度假空间 · 导览样板</span></div>
      <div class="resort-intro"><div><p class="resort-kicker">在抵达之前，先走进山间。</p><h1 id="resort-title">云栖山庄<span>留一段时间，给山与自己。</span></h1></div><p class="resort-lead">沿着三维空间，看看住处，找到一餐一茶，<br class="resort-desktop-break">也为闲下来的时光，挑一处去处。</p></div>
      <p class="resort-concept">概念体验 · 云栖山庄为虚构的度假导览模板，场景与设施名称用于演示。</p>
    </section>
    <section class="resort-tour" aria-labelledby="resort-tour-title">
      <div class="resort-tour-heading"><div><p class="resort-kicker">把度假的第一步，留在这里</p><h2 id="resort-tour-title">走进山庄</h2></div><p>拖动旋转 · 滚动或双指缩放 · 点击点位查看介绍</p></div>
      <div class="resort-tour-layout"><div class="resort-viewer-panel"><div class="resort-viewer-stage"><div class="resort-viewer-mount"></div><div class="resort-viewer-status" role="status">${config.sourceUrl?'正在打开山庄三维场景…':'三维场景正在准备，您可以先浏览下方空间介绍。'}</div><span class="resort-viewer-caption">YUNQI · 空间导览</span></div><div class="resort-viewer-footer"><span data-resort-count>三维点云场景</span><button type="button" data-resort-reset disabled>回到全景 <span aria-hidden="true">↗</span></button></div></div>
      <aside class="resort-guide" aria-label="空间导览"><p class="resort-guide-label">想从哪里开始</p><div class="resort-filters" role="group" aria-label="空间分类">${resortCategories.map(category=>`<button type="button" data-resort-category="${category.id}" aria-pressed="${category.id==='all'}">${category.label}</button>`).join('')}</div><div class="resort-points"></div><p class="resort-guide-note">点位随场景视角移动。<br>选择名称，也可以直接前往对应空间。</p></aside></div>
    </section>
    <section class="resort-stay" aria-labelledby="resort-stay-title"><div><p class="resort-kicker">从一晚好眠，到一整日闲适</p><h2 id="resort-stay-title">把日子，过慢一点。</h2></div><div class="resort-stay-grid"><article><span>住</span><h3>客房</h3><p>推窗见景，归来有处。先看看不同住处，在空间里感受休息的尺度。</p></article><article><span>抵</span><h3>前台</h3><p>从抵达开始熟悉山庄。接待、问询与出行信息，在这里找到方向。</p></article><article><span>食</span><h3>餐饮</h3><p>为一顿饭留些时间。从早餐到晚茶，发现停下来相聚的地方。</p></article><article><span>游</span><h3>娱乐</h3><p>散步、闲坐，或与朋友共度片刻。让一天的安排，多一点随心。</p></article></div></section>
    <footer class="resort-source"><div><p class="resort-kicker">关于这个样板</p><p>本页展示窗后城的三维空间导览方式。云栖山庄、设施分区及介绍均为概念设定，不代表真实度假村的设施、预订信息或已达成的合作。</p></div><div><p class="resort-kicker">场景资料</p><p data-resort-source></p><p class="resort-source-note">导览样板，采用羊角村公开扫描数据，设施与房号为演示配置。</p></div></footer>
    <dialog class="resort-dialog" aria-labelledby="resort-detail-title" aria-describedby="resort-detail-description"><button type="button" class="resort-dialog-close" aria-label="关闭空间介绍">×</button><p class="resort-kicker" data-resort-detail-category></p><h2 id="resort-detail-title"></h2><p id="resort-detail-description"></p><p class="resort-detail-note">云栖山庄 · 概念导览点位</p><button type="button" class="resort-dialog-done">继续探索</button></dialog>`;
  const source = main.querySelector('[data-resort-source]');
  source.textContent = [config.sourceLabel,config.sourceCredit,config.sourceLicense].filter(Boolean).join(' · ');
  if (config.sourcePage && /^https:\/\//i.test(config.sourcePage)) {
    const link = document.createElement('a');
    link.href = config.sourcePage;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    link.textContent = '查看原始资料 ↗';
    source.append(document.createElement('br'),link);
  }
  if (config.sourceLicenseUrl && /^https:\/\//i.test(config.sourceLicenseUrl)) {
    const license = document.createElement('a');
    license.href = config.sourceLicenseUrl;
    license.target = '_blank';
    license.rel = 'noopener noreferrer';
    license.textContent = 'CC BY 4.0 许可';
    source.append(document.createTextNode(' · '),license);
  }
  const dialog = main.querySelector('.resort-dialog');
  const status = main.querySelector('.resort-viewer-status');
  const reset = main.querySelector('[data-resort-reset]');
  const list = main.querySelector('.resort-points');
  const categoryButtons = [...main.querySelectorAll('[data-resort-category]')];
  let viewer, frame, initialCamera, category = 'all';
  let visiblePoints = config.points;
  function showPoint(point) {
    main.querySelector('[data-resort-detail-category]').textContent = resortCategories.find(item=>item.id===point.category).label;
    main.querySelector('#resort-detail-title').textContent = point.title;
    main.querySelector('#resort-detail-description').textContent = point.description;
    if (!dialog.open) dialog.showModal();
  }
  function syncAnnotations() {
    const overlay = bindResortAnnotations(viewer,visiblePoints,showPoint);
    frame.contentDocument.body.append(overlay);
    for (const marker of overlay.querySelectorAll('[data-aid]')) {
      const point = visiblePoints.find(item=>item.id===marker.dataset.aid);
      marker.setAttribute('tabindex','0');
      marker.setAttribute('role','button');
      marker.setAttribute('aria-label',point.title);
      marker.querySelector('.olv-anno-halo')?.setAttribute('r','20');
      marker.onkeydown = event=>{
        if (event.key==='Enter' || event.key===' ') { event.preventDefault(); viewer.annotate.select(point.id); }
      };
    }
  }
  function renderList() {
    visiblePoints = config.points.filter(point=>category==='all'||point.category===category);
    list.innerHTML = visiblePoints.length ? visiblePoints.map((point,index)=>`<button type="button" class="resort-point" data-resort-point="${escapeHtml(point.id)}"><span class="resort-point-number">${String(index+1).padStart(2,'0')}</span><span><strong>${escapeHtml(point.title)}</strong><small>${resortCategories.find(item=>item.id===point.category).label}</small></span><span aria-hidden="true">↗</span></button>`).join('') : '<p class="resort-empty">这一类空间正在准备，先看看其他区域。</p>';
    list.querySelectorAll('[data-resort-point]').forEach(button=>button.addEventListener('click',()=>{
      const point = visiblePoints.find(item=>item.id===button.dataset.resortPoint);
      if (viewer) viewer.jumpToAnnotation(point.id);
      showPoint(point);
    }));
    categoryButtons.forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.resortCategory===category)));
    if (viewer) syncAnnotations();
  }
  categoryButtons.forEach(button=>button.addEventListener('click',()=>{category=button.dataset.resortCategory;renderList();}));
  main.querySelector('.resort-dialog-close').addEventListener('click',()=>dialog.close());
  main.querySelector('.resort-dialog-done').addEventListener('click',()=>dialog.close());
  dialog.addEventListener('close',()=>viewer?.annotate.select(null));
  dialog.addEventListener('click',event=>{
    if (event.target!==dialog) return;
    const rect=dialog.getBoundingClientRect();
    if (event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom) dialog.close();
  });
  reset.addEventListener('click',()=>{if(viewer&&initialCamera)viewer.applyCameraState(initialCamera);});
  renderList();
  if (!config.sourceUrl) return;
  frame = document.createElement('iframe');
  frame.title = '云栖山庄三维空间导览';
  frame.allow = 'fullscreen';
  frame.allowFullscreen = true;
  frame.src = buildResortViewerUrl(config,location.href);
  function connectViewer() {
    if (viewer) return;
    const bridge=frame.contentWindow?.pocketworldOlv;
    if (!bridge?.viewer) return;
    viewer=bridge.viewer;
    const style=frame.contentDocument.createElement('style');
    style.textContent=annotationStyle;
    frame.contentDocument.head.append(style);
    if (config.initialCamera) viewer.applyCameraState(config.initialCamera);
    initialCamera=config.initialCamera || viewer.getCameraState();
    syncAnnotations();
    reset.disabled=false;
    status.hidden=true;
    main.querySelector('[data-resort-count]').textContent=`${Number(bridge.cloud.sourcePointCount).toLocaleString('zh-CN')} 个点 · 三维空间`;
  }
  const onMessage=event=>{
    const data=event.data;
    if (event.origin!==location.origin||event.source!==frame.contentWindow||data?.source!=='pocketworld-olv'||data.protocol!=='PW_POINT_CLOUD_STREAM_V1') return;
    if(data.type==='ready'||data.type==='progress') connectViewer();
    if(data.type==='error') {status.hidden=false;status.textContent='场景暂时无法打开。请刷新页面重试，空间介绍仍可浏览。';}
  };
  window.addEventListener('message',onMessage);
  frame.addEventListener('load',connectViewer);
  window.addEventListener('pagehide',()=>window.removeEventListener('message',onMessage),{once:true});
  main.querySelector('.resort-viewer-mount').append(frame);
}

// Adapted interaction semantics from MIT Sculpt ModelAnnotationCanvas.tsx,
// revision 2e0e11d76650748ffd577b45943cd063cf097cb4. See SURFACE_COMMENTS_NOTICE.
// Geometry intersection and projection use the existing pinned Three.js engine.
export function validateAnchor(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid surface anchor');
  const vector = value => {
    if (!Array.isArray(value) || value.length !== 3 || value.some(v => !Number.isFinite(v) || Math.abs(v) > 1e12)) throw new Error('Invalid surface vector');
    return [...value];
  };
  const anchor = {position: vector(input.position)};
  if (input.normal != null) {
    anchor.normal = vector(input.normal);
    if (anchor.normal.every(v => v === 0)) throw new Error('Invalid surface normal');
  }
  if ((input.cameraPosition != null) !== (input.cameraTarget != null)) throw new Error('Incomplete surface camera');
  if (input.cameraPosition != null) {
    anchor.cameraPosition = vector(input.cameraPosition); anchor.cameraTarget = vector(input.cameraTarget);
  }
  return anchor;
}

export function createSurfaceComments({THREE, canvas, camera, controls, getModel, getFormat, getOverviewDistance, onMarkerInteraction, emit}) {
  const raycaster = new THREE.Raycaster();
  let enabled = false, markers = [], down = null, disposed = false, markerSignature = null;
  const pointers = new Set();
  const document = canvas.ownerDocument;
  let layoutSignature = 'null';
  let referenceProjectionScale = null;
  function publishLayout(layout) {
    const signature = JSON.stringify(layout);
    if (signature === layoutSignature) return;
    layoutSignature = signature;
    emitEvent('pw-viewer-surface-marker-layout', {layout});
  }
  const overlay = document?.createElement('div');
  if (overlay) {
    overlay.setAttribute('aria-label', '表面评论');
    Object.assign(overlay.style, {position:'fixed',inset:'0',pointerEvents:'none',zIndex:'5',overflow:'hidden'});
    document.body.appendChild(overlay);
  }
  function emitEvent(type, detail) { emit?.(type, detail); }
  const supported = () => ['glb','ply'].includes(getFormat());
  function setMode(value) {
    if (typeof value !== 'boolean') throw new Error('Invalid surface comment mode');
    if (value && !supported()) throw new Error('Surface comments require a loaded GLB or PLY');
    enabled = value; down = null; pointers.clear();
    if (enabled) controls.autoRotate = false;
    update();
  }
  function setMarkers(values) {
    if (!Array.isArray(values) || values.length > 256) throw new Error('Too many surface markers');
    const ids = new Set();
    const validated = values.map(value => {
      if (!value || typeof value.id !== 'string' || !value.id.length || value.id.length > 128 || ids.has(value.id) ||
          !Number.isInteger(value.number) || value.number < 1 || value.number > 999999 ||
          ('selected' in value && typeof value.selected !== 'boolean')) throw new Error('Invalid surface marker');
      ids.add(value.id);
      const previewText=value.previewText ?? '',previewImages=value.previewImages ?? [];
      if(typeof previewText !== 'string' || previewText.length>2000 || !Array.isArray(previewImages) || previewImages.length>3 || previewImages.some(src=>{
        if(typeof src!=='string' || src.length>4096) return true;
        try { const url=new URL(src);return !!url.username || !!url.password || !(url.protocol==='https:' ||
          (url.protocol==='http:' && ['localhost','127.0.0.1','[::1]'].includes(url.hostname))); } catch {return true;}
      })) throw new Error('Invalid surface comment content');
      return {id:value.id,number:value.number,selected:value.selected === true,anchor:validateAnchor(value.anchor),previewText,previewImages};
    });
    const signature = JSON.stringify(validated);
    // Polling/host echoes must not remove the native pointerdown target before
    // pointerup/click. Content and identity changes still rebuild atomically.
    if (signature === markerSignature) { update(); return; }
    markerSignature = signature;
    for (const marker of markers) marker.animation?.cancel();
    overlay?.replaceChildren(); markers = validated;
    for (const marker of markers) {
      if (!overlay) continue;
      const button = document.createElement('button'); marker.button = button;
      // Numbers remain internal ordering metadata in every marker state.
      button.type = 'button'; button.textContent = '';
      button.setAttribute('aria-label', '查看评论点位');
      button.setAttribute('aria-pressed', String(marker.selected));
      Object.assign(button.style, {position:'absolute',width:'26px',height:'26px',borderRadius:'50%',
        border:'0',background:'transparent',color:'white',padding:'0',pointerEvents:'auto',
        zIndex:marker.selected?'2':'1',transform:'translate(-50%,-50%)',cursor:'pointer'});
      const halo = document.createElement('span'); marker.halo = halo;
      halo.setAttribute('aria-hidden', 'true');
      Object.assign(halo.style, {position:'absolute',left:'50%',top:'50%',width:'22px',height:'22px',
        borderRadius:'50%',background:'#fff',opacity:'.3',filter:'blur(4px)',
        transform:'translate(-50%,-50%)',pointerEvents:'none'});
      const dot = document.createElement('span'); marker.dot = dot;
      dot.setAttribute('aria-hidden', 'true');
      Object.assign(dot.style, {position:'absolute',left:'50%',top:'50%',borderRadius:'50%',
        background:'#fff',transform:'translate(-50%,-50%)',pointerEvents:'none'});
      button.appendChild(halo); button.appendChild(dot);
      styleSelection(marker);
      if (!document.defaultView?.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
        marker.animation = halo.animate?.([
          {opacity:.2,transform:'translate(-50%,-50%) scale(.85)'},
          {opacity:.6,transform:'translate(-50%,-50%) scale(1.3)'},
          {opacity:.2,transform:'translate(-50%,-50%) scale(.85)'},
        ], {duration:2400,iterations:Infinity,easing:'ease-in-out'});
      }
      const stopRotation = () => { controls.autoRotate = false; onMarkerInteraction?.(); };
      button.addEventListener('pointerdown', event => { event.stopPropagation(); if (!enabled) stopRotation(); });
      // The pin is above the canvas. Preserve OrbitControls' wheel handling
      // there, while leaving scrolling inside a comment card to the browser.
      button.addEventListener('wheel', event => {
        if (enabled || marker.content?.contains?.(event.target)) return;
        const Wheel = document.defaultView?.WheelEvent;
        if (!Wheel) return;
        event.preventDefault(); event.stopPropagation();
        canvas.dispatchEvent(new Wheel('wheel', {
          bubbles:true, cancelable:true, deltaX:event.deltaX, deltaY:event.deltaY,
          deltaZ:event.deltaZ, deltaMode:event.deltaMode,
          clientX:event.clientX, clientY:event.clientY,
          ctrlKey:event.ctrlKey, shiftKey:event.shiftKey,
          altKey:event.altKey, metaKey:event.metaKey,
        }));
      }, {passive:false});
      button.addEventListener('click', event => {
        event.stopPropagation();
        if (enabled || marker.occluded || marker.content?.contains?.(event.target)) return;
        stopRotation();
        // Native click/keyboard activation must show feedback locally, without
        // waiting for an asynchronous Flutter bridge echo.
        const wasSelected = marker.selected;
        for (const other of markers) {
          other.selected = !wasSelected && other.id === marker.id;
          other.button.setAttribute('aria-pressed', String(other.selected));
          styleSelection(other);
        }
        update();
        emitEvent('pw-viewer-surface-marker-selected', {id:marker.id});
      });
      if(marker.previewText || marker.previewImages.length) {
        const content=document.createElement('span');marker.content=content;
        content.setAttribute('data-comment-content',marker.id);
        Object.assign(content.style,{display:'none',position:'absolute',left:'34px',top:'-10px',width:'min(240px,55vw)',maxHeight:'240px',overflow:'auto',
          padding:'12px',borderRadius:'16px',background:'rgba(24,24,28,.94)',border:'1px solid #ffffff30',color:'#fff',textAlign:'left',
          font:'14px/1.5 system-ui',whiteSpace:'pre-wrap',boxShadow:'0 6px 24px #0006',boxSizing:'border-box'});
        if(marker.previewText){const text=document.createElement('span');text.textContent=marker.previewText;content.appendChild(text);}
        marker.images=marker.previewImages.map((src,index)=>{
          const img=document.createElement('img');img.alt=`评论图片 ${index+1}`;img.loading='lazy';img.referrerPolicy='no-referrer';
          Object.assign(img.style,{display:'block',maxWidth:'100%',maxHeight:'144px',objectFit:'contain',borderRadius:'8px',marginTop:'8px'});
          content.appendChild(img);return {img,src};
        });
        button.appendChild(content);
      }
      overlay.appendChild(button);
    }
    update();
  }
  function styleSelection(marker, scale = 1) {
    const size = (marker.selected ? 12 : 9) * scale;
    marker.dot.style.width = `${size}px`;
    marker.dot.style.height = `${size}px`;
    marker.halo.style.width = `${22 * scale}px`;
    marker.halo.style.height = `${22 * scale}px`;
    marker.halo.style.filter = `blur(${4 * scale}px)`;
    marker.halo.style.boxShadow = marker.selected
      ? `0 0 ${12 * scale}px ${5 * scale}px #fff9`
      : `0 0 ${8 * scale}px ${2 * scale}px #fff6`;
    marker.button.style.zIndex = marker.selected ? '2' : '1';
  }
  function visible(node, root) {
    for (let object = node; object; object = object.parent) {
      if (!object.visible) return false;
      if (object === root) break;
    }
    return true;
  }
  function intersections(root) {
    // A point cloud is not an opaque mesh surface. Do not scan its entire
    // vertex buffer for every overlay pin on every frame; only meshes occlude.
    const hits=[];
    root.traverse(node => { if (node.isMesh && visible(node,root)) raycaster.intersectObject(node,false,hits); });
    return hits.sort((a,b)=>a.distance-b.distance);
  }
  function pickIntersections(root, rect, event) {
    const hits=intersections(root);
    const tolerance=6; // CSS pixels; independent of device pixel ratio/model units.
    root.traverse(node => {
      if (!node.isPoints || !visible(node,root) || node.material?.visible === false) return;
      const geometry=node.geometry;
      if (!geometry.getAttribute('position')) return;
      if (!geometry.boundingSphere) geometry.computeBoundingSphere();
      const sphere=geometry.boundingSphere.clone().applyMatrix4(node.matrixWorld);
      const depth=sphere.center.clone().sub(camera.position).dot(camera.getWorldDirection(new THREE.Vector3()))+sphere.radius;
      if (!(depth>0)) return;
      const height=camera.isPerspectiveCamera ? camera.getViewSize(depth,new THREE.Vector2()).y :
        (camera.top-camera.bottom)/camera.zoom;
      const scale=node.getWorldScale(new THREE.Vector3());
      const minScale=Math.min(Math.abs(scale.x),Math.abs(scale.y),Math.abs(scale.z));
      if (!(minScale>0)) return;
      // Points.raycast normalizes by object.scale (not ancestor world scale).
      // Supply a conservative world-space radius, then screen-filter its hits.
      raycaster.params.Points.threshold=height/rect.height*tolerance *
        (Math.abs(node.scale.x)+Math.abs(node.scale.y)+Math.abs(node.scale.z))/3/minScale;
      const candidates=raycaster.intersectObject(node,false);
      for (const hit of candidates) {
        if (!Number.isInteger(hit.index)) continue;
        const world=new THREE.Vector3().fromBufferAttribute(geometry.getAttribute('position'),hit.index).applyMatrix4(node.matrixWorld);
        const projected=world.clone().project(camera);
        const dx=rect.left+(projected.x+1)*rect.width/2-event.clientX;
        const dy=rect.top+(1-projected.y)*rect.height/2-event.clientY;
        if (projected.z>=-1 && projected.z<=1 && Math.hypot(dx,dy)<=tolerance) hits.push({...hit,point:world});
      }
    });
    return hits.sort((a,b)=>a.distance-b.distance);
  }
  function pick(event) {
    const root = getModel();
    if (!enabled || disposed || controls.enabled === false || !root || !supported()) return;
    const rect = canvas.getBoundingClientRect();
    if (!(rect.width > 0 && rect.height > 0)) return;
    root.updateWorldMatrix(true,true); camera.updateMatrixWorld();
    raycaster.setFromCamera(new THREE.Vector2((event.clientX-rect.left)/rect.width*2-1, -(event.clientY-rect.top)/rect.height*2+1),camera);
    const hit = pickIntersections(root,rect,event)[0];
    if (!hit) return;
    const anchor = {position:root.worldToLocal(hit.point.clone()).toArray(),
      cameraPosition:camera.position.toArray(),cameraTarget:controls.target.toArray()};
    if (hit.face) {
      const relative = new THREE.Matrix4().copy(root.matrixWorld).invert().multiply(hit.object.matrixWorld);
      anchor.normal = hit.face.normal.clone().applyNormalMatrix(new THREE.Matrix3().getNormalMatrix(relative)).toArray();
    }
    try { emitEvent('pw-viewer-surface-picked', {anchor:validateAnchor(anchor)}); } catch { /* Degenerate transforms cannot create valid anchors. */ }
  }
  const handlers = {
    pointerdown(event) {
      pointers.add(event.pointerId);
      if (pointers.size !== 1 || event.isPrimary === false || (event.button != null && event.button !== 0)) { down = null; return; }
      down = {id:event.pointerId,x:event.clientX,y:event.clientY,moved:false};
    },
    pointermove(event) {
      if (down?.id === event.pointerId && Math.hypot(event.clientX-down.x,event.clientY-down.y) > 4) down.moved = true;
    },
    pointerup(event) {
      const tap = down?.id === event.pointerId && !down.moved && pointers.size === 1 && Math.hypot(event.clientX-down.x,event.clientY-down.y) <= 4;
      down = null; pointers.delete(event.pointerId);
      if (tap) pick(event);
    },
    pointercancel(event) { down = null; pointers.delete(event.pointerId); },
    lostpointercapture(event) { down = null; pointers.delete(event.pointerId); },
  };
  for (const [name,handler] of Object.entries(handlers)) canvas.addEventListener?.(name,handler);
  function update() {
    const root = getModel();
    // Picking presents the unannotated asset. Keep saved marker state intact
    // so cancellation/selection can restore it without a reload or DOM churn.
    if (overlay) {
      overlay.style.display = enabled ? 'none' : 'block';
      overlay.setAttribute('aria-hidden', String(enabled));
    }
    if (!overlay || !root || disposed || enabled) { publishLayout(null); return; }
    root.updateWorldMatrix(true,true);camera.updateMatrixWorld();
    const rect = canvas.getBoundingClientRect();
    const overview = getOverviewDistance?.();
    if (referenceProjectionScale == null && Number.isFinite(overview) && overview > 0 && rect.height > 1) {
      referenceProjectionScale = rect.height / camera.getViewSize(overview, new THREE.Vector2()).y;
    }
    const layouts = [];
    const hasSelection = markers.some(marker => marker.selected);
    for (const marker of markers) {
      const world = root.localToWorld(new THREE.Vector3(...marker.anchor.position));
      const projected = world.clone().project(camera);
      const depth = world.clone().sub(camera.position).dot(camera.getWorldDirection(new THREE.Vector3()));
      if (referenceProjectionScale > 0 && depth > 0 && rect.height > 1) {
        const projectionScale = rect.height / camera.getViewSize(depth, new THREE.Vector2()).y;
        styleSelection(marker, projectionScale / referenceProjectionScale);
      }
      const shown = root.visible && supported() && projected.z >= -1 && projected.z <= 1 && Math.abs(projected.x) <= 1 && Math.abs(projected.y) <= 1;
      marker.button.style.display = shown ? 'block' : 'none';
      if (!shown) continue;
      marker.button.style.left = `${rect.left+(projected.x+1)*rect.width/2}px`;
      marker.button.style.top = `${rect.top+(1-projected.y)*rect.height/2}px`;
      const direction=world.clone().sub(camera.position),distance=direction.length();
      raycaster.set(camera.position,direction.normalize());
      const hit=intersections(root)[0];
      const occluded=hit && hit.distance < distance - Math.max(1e-6,distance*1e-5);
      marker.occluded = Boolean(occluded);
      marker.button.style.opacity = hasSelection && !marker.selected ? '0.08' : occluded ? '0.25' : '1';
      marker.button.disabled = Boolean(occluded);
      marker.button.style.pointerEvents = occluded ? 'none' : 'auto';
      const overview=getOverviewDistance?.();
      const zoom=Number.isFinite(overview) && overview>0 ? overview/camera.position.distanceTo(controls.target) : 1;
      const near=!occluded && zoom >= (marker.expanded ? 1.2 : 1.35);
      marker.expanded=near;
      if (!occluded && (near || marker.selected)) layouts.push({
        id:marker.id, x:Math.round((projected.x+1)*500)/1000,
        y:Math.round((1-projected.y)*500)/1000,
        expanded:near, selected:marker.selected,
      });
      if(marker.content) {
        // UI reveal relative to the upstream overview framing, independent of model units.
        const contentVisible = !occluded && (marker.selected || (!hasSelection && near));
        marker.content.style.display=contentVisible?'block':'none';
        if(contentVisible) for(const {img,src} of marker.images) if(img.src!==src) img.src=src;
        const x=rect.left+(projected.x+1)*rect.width/2;
        const cardWidth=Math.min(260,Math.max(120,rect.width-32));
        const preferred=projected.x>0 ? x-cardWidth-24 : x+24;
        const left=Math.max(rect.left+12,Math.min(preferred,rect.left+rect.width-cardWidth-12));
        marker.content.style.width=`${cardWidth}px`;
        marker.content.style.left=`${left-x+13}px`;
        marker.content.style.right='auto';
        marker.content.style.top=projected.y<-.35 ? 'auto':'-10px';
        marker.content.style.bottom=projected.y<-.35 ? '-10px':'auto';
      }
    }
    const active = layouts.find(value=>value.expanded && value.selected) ??
      layouts.find(value=>value.expanded) ?? layouts.find(value=>value.selected);
    publishLayout(active ? {id:active.id,x:active.x,y:active.y,expanded:active.expanded} : null);
  }
  function focus(input) {
    if (!getModel() || !supported()) throw new Error('Surface comments require a loaded GLB or PLY');
    const anchor = validateAnchor(input);
    if (!anchor.cameraPosition) throw new Error('Surface comment has no camera snapshot');
    const position = new THREE.Vector3(...anchor.cameraPosition),target = new THREE.Vector3(...anchor.cameraTarget);
    if (position.distanceToSquared(target) < 1e-18) throw new Error('Invalid surface camera distance');
    controls.autoRotate = false;
    // Flush upstream OrbitControls damping before applying the stored view.
    const damping=controls.enableDamping;
    controls.enableDamping=false;controls.update();
    camera.position.copy(position);controls.target.copy(target);controls.update();controls.enableDamping=damping;
    update();
  }
  function clear() { enabled=false;referenceProjectionScale=null;down=null;pointers.clear();for(const marker of markers)marker.animation?.cancel();markers=[];markerSignature=null;overlay?.replaceChildren();publishLayout(null); }
  function dispose() { disposed=true;clear();for(const [name,handler] of Object.entries(handlers))canvas.removeEventListener?.(name,handler);overlay?.remove(); }
  return {setMode,setMarkers,focus,update,clear,dispose,get enabled(){return enabled;}};
}

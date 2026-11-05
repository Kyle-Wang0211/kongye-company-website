import {t,localeEvent} from './site-l10n.mjs?v=rds-web-20261104-7931926b3d74';
const stage=document.querySelector('.community-screen-stage');
const links=[...document.querySelectorAll('.community-feature-screen')];
const choices=[...document.querySelectorAll('.community-screen-choice')];
const keys=['siteScreenOne','siteScreenTwo','siteScreenThree'];
let selected=1;
try{const raw=sessionStorage.getItem('pw-community-screen'),value=Number(raw);if(raw!==null&&Number.isInteger(value)&&value>=0&&value<3)selected=value;}catch{}
const relative=index=>(index-selected+4)%3-1;
function select(index){
 selected=(index+3)%3;
 links.forEach((link,i)=>{link.dataset.position=['left','center','right'][relative(i)+1];choices[i].setAttribute('aria-pressed',String(i===selected));});
 try{sessionStorage.setItem('pw-community-screen',String(selected));}catch{}
}
choices.forEach((button,index)=>button.addEventListener('click',()=>select(index)));
document.querySelector('.community-screen-switcher').addEventListener('keydown',event=>{
 if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;
 event.preventDefault();select(event.key==='Home'?0:event.key==='End'?2:selected+(event.key==='ArrowLeft'?-1:1));choices[selected].focus();
});
let down=null,suppressClickUntil=0;
stage.addEventListener('pointerdown',event=>{if(event.isPrimary&&event.button===0)down={x:event.clientX,y:event.clientY,id:event.pointerId};});
stage.addEventListener('pointerup',event=>{
 if(!down||event.pointerId!==down.id)return;
 const dx=event.clientX-down.x,dy=event.clientY-down.y;down=null;
 if(Math.abs(dx)>40&&Math.abs(dx)>Math.abs(dy)){select(selected+(dx<0?1:-1));suppressClickUntil=performance.now()+250;}
});
stage.addEventListener('pointercancel',()=>{down=null;});
stage.addEventListener('click',event=>{if(performance.now()<suppressClickUntil)event.preventDefault();},true);
function labels(){
 choices.forEach((button,i)=>button.setAttribute('aria-label',t(keys[i])));
}
window.addEventListener(localeEvent,labels);
select(selected);labels();

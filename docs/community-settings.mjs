const menu=document.querySelector('#account-menu');
const dialog=document.querySelector('#site-settings');
const opener=document.querySelector('#open-settings');
let returnFocus;
for(const button of [opener,document.querySelector('#open-sidebar-settings')].filter(Boolean))button.addEventListener('click',()=>{returnFocus=button;menu.open=false;dialog.showModal();});
document.querySelector('#close-settings').addEventListener('click',()=>dialog.close());
dialog.addEventListener('close',()=>{const target=returnFocus?.offsetParent?returnFocus:document.querySelector('#account-summary');target.focus();});
document.addEventListener('click',event=>{if(!menu.contains(event.target))menu.open=false;});
document.addEventListener('keydown',event=>{if(event.key==='Escape')menu.open=false;});

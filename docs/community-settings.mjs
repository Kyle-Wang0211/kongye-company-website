const menu=document.querySelector('#account-menu');
const dialog=document.querySelector('#site-settings');
const opener=document.querySelector('#open-settings');
opener.addEventListener('click',()=>{menu.open=false;dialog.showModal();});
document.querySelector('#close-settings').addEventListener('click',()=>dialog.close());
dialog.addEventListener('close',()=>document.querySelector('#account-summary').focus());
document.addEventListener('click',event=>{if(!menu.contains(event.target))menu.open=false;});
document.addEventListener('keydown',event=>{if(event.key==='Escape')menu.open=false;});

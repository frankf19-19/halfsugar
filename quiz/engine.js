// 微糖心理測驗共用引擎：資料放在 window.QZ（各測驗自己的 data.js），版面沿用 quiz.css
(function(){
var Z=window.QZ,Q=Z.q,R=Z.r,K=Object.keys(R),i=0,sc,best,$=function(id){return document.getElementById(id)};
function show(id){['intro','quiz','result'].forEach(function(s){$(s).hidden=s!==id});window.scrollTo(0,0)}
function ask(){var q=Q[i];$('qn').textContent='第 '+(i+1)+' 題';$('qtot').textContent='共 '+Q.length+' 題';$('prog').style.width=(i/Q.length*100)+'%';$('qt').textContent=q[0];
 var o=$('opts');o.innerHTML='';q[1].forEach(function(t,k){var b=document.createElement('button');b.className='opt';b.textContent=t;b.onclick=function(){sc[K[k]]++;i++;i<Q.length?ask():done()};o.appendChild(b)});o.firstChild.focus()}
function done(){best=K[0];K.forEach(function(k){if(sc[k]>sc[best])best=k});var r=R[best];
 try{localStorage.setItem(Z.store,best)}catch(e){}
 $('rw').textContent=r.w;$('rp').textContent=r.p;$('rd').textContent=r.d;
 var dl=$('rinfo');dl.innerHTML='';Z.rows.forEach(function(row){var dt=document.createElement('dt'),dd=document.createElement('dd');dt.textContent=row[1];dd.textContent=r[row[0]];dl.appendChild(dt);dl.appendChild(dd)});
 var txt=Z.share.replace('{w}',r.w).replace('{d}',r.d);
 $('line').href='https://social-plugins.line.me/lineit/share?url='+encodeURIComponent(Z.url)+'&text='+encodeURIComponent(txt);
 $('threads').href='https://www.threads.net/intent/post?text='+encodeURIComponent(txt+' '+Z.url);
 show('result')}
function wrap(ctx,text,x,y,maxW,lh){var line='',lines=[];for(var c of text){if(ctx.measureText(line+c).width>maxW){lines.push(line);line=c}else line+=c}lines.push(line);lines.forEach(function(l,n){ctx.fillText(l,x,y+n*lh)});return y+lines.length*lh}
function card(){var r=R[best],c=document.createElement('canvas');c.width=1080;c.height=1920;var x=c.getContext('2d');
 var serif='"Noto Serif TC", "PingFang TC", serif',sans='"PingFang TC","Noto Sans TC",sans-serif';
 x.fillStyle='#F4EFE5';x.fillRect(0,0,1080,1920);x.fillStyle='#FCFAF4';x.fillRect(70,150,940,1560);x.strokeStyle='#D9CFB8';x.lineWidth=6;x.strokeRect(70,150,940,1560);
 x.textAlign='center';x.fillStyle='#6B5D45';x.font='500 40px '+serif;x.fillText(Z.title,540,290);
 x.fillStyle='#D9CFB8';x.fillRect(170,340,740,4);
 x.fillStyle='#6B5D45';x.font='400 44px '+serif;x.fillText(Z.lead,540,470);
 x.fillStyle='#1d1a17';x.font='900 '+(r.w.length>5?120:150)+'px '+serif;x.fillText(r.w,540,660);
 x.fillStyle='#6B5D45';x.font='400 40px '+serif;x.fillText(r.p,540,740);
 x.fillStyle='#A63F58';x.font='900 52px '+serif;var y=wrap(x,r.d,540,880,780,72);
 x.textAlign='left';
 Z.card.forEach(function(row){x.fillStyle='#6B5D45';x.font='500 32px '+sans;x.fillText(row[1],170,y+60);x.fillStyle='#1d1a17';x.font='400 40px '+sans;y=wrap(x,r[row[0]],170,y+120,740,60)});
 x.textAlign='center';x.fillStyle='#A63F58';x.font='500 40px '+serif;x.fillText(Z.cta,540,Math.max(y+110,1600));
 x.fillStyle='#1d1a17';x.font='900 46px '+serif;x.fillText('微糖 1/3 Sugar',540,1810);
 x.fillStyle='#6B5D45';x.font='400 32px '+sans;x.fillText(Z.url.replace('https://',''),540,1866);
 return c}
function saveImg(){var go=function(){var c=card();c.toBlob(function(b){var f=new File([b],'微糖測驗結果.png',{type:'image/png'});
  if(navigator.canShare&&navigator.canShare({files:[f]})){navigator.share({files:[f],title:Z.title}).catch(function(){})}
  else{var a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='微糖測驗結果.png';document.body.appendChild(a);a.click();a.remove();$('img').textContent='已存成圖片，分享到限動吧'}},'image/png')};
 (document.fonts&&document.fonts.ready?document.fonts.ready:Promise.resolve()).then(go)}
$('start').onclick=function(){i=0;sc={};K.forEach(function(k){sc[k]=0});show('quiz');ask()};
$('again').onclick=function(){show('intro')};
$('img').onclick=saveImg;
})();

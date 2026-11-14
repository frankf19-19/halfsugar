// 戀愛心理測驗：7 題，每個選項對應一型（A 成熟大叔、B 陽光小狼狗、C 溫柔暖男、D 霸氣總裁）
(function(){
var Q=[
 ['週末早上醒來，你最想？',['睡到自然醒，有人幫我買好早午餐','被拉去爬山、衝浪，曬一整天太陽','窩在家一起追劇、叫外送','跟著他去一間沒去過的高級餐廳']],
 ['吵架的時候，你希望對方？',['冷靜聽我說完，再慢慢講道理','撒嬌道歉，抱一下就好','跟我一起想辦法，不要冷戰','直接說出他的想法，不拐彎']],
 ['理想的約會是？',['安靜的餐酒館，聊到忘記時間','遊樂園、演唱會，越熱鬧越好','一起逛市集、做飯，很生活感','他全部安排好，我只要負責美美出門']],
 ['你最受不了另一半？',['幼稚、情緒化','無聊、沒有活力','不懂我的情緒','沒主見、什麼都說隨便']],
 ['你生病的時候，最希望？',['他已經掛好號，還送來熱粥','他翹班來陪我，在旁邊碎碎念','他傳訊息問我還好嗎、需要什麼','他說「我安排好了，你什麼都不用管」']],
 ['朋友形容你的另一半，最好是？',['好穩重、好有安全感','好可愛、好會撒嬌','好溫柔、跟你好像','好有氣場、好帥']],
 ['旅行時你是？',['跟著他就好，他會把一切打點好','說走就走，行程隨時改','一起做功課，邊走邊找好吃的','住好一點、吃好一點，他來決定']]];
var R={
 A:{w:'成熟大叔',p:'Mature & Steady',d:'需要一個讓你可以放心示弱的人。',l:'你白天很能幹，私底下其實很想被照顧。成熟大叔情緒穩定、說到做到，會注意到你累了、餓了，讓你不用一直逞強。',date:'安靜的餐酒館，他先訂好位，記得你上次說想吃的那道菜。',tip:'成熟不等於單身——第一次聊天就直接問清楚，再開始投入。'},
 B:{w:'陽光小狼狗',p:'Sunny & Sweet',d:'需要一個讓你每天都想笑的人。',l:'你喜歡熱鬧、喜歡新鮮感，跟熱情、黏人、有活力的人在一起，你會變回最輕鬆的自己。',date:'演唱會、遊樂園或夜市，玩到最後一班捷運。',tip:'熱情很迷人，也記得看他能不能在你需要時穩住你。'},
 C:{w:'溫柔暖男',p:'Warm & Understanding',d:'需要一個懂你、像好朋友的人。',l:'你重視溝通和陪伴，最在意的是「他懂不懂我」。溫柔暖男和你同步，願意一起想辦法，不讓你一個人面對。',date:'週末一起逛市集、回家做一頓飯，邊吃邊聊。',tip:'溫柔的人也有需求，記得也問問他今天過得好嗎。'},
 D:{w:'霸氣總裁',p:'Bold & Decisive',d:'需要一個有主見、帶著你走的人。',l:'你欣賞有氣場、有方向的人。他決定事情很快、說到做到，跟他在一起，你可以放心把方向盤交出去。',date:'他全部安排好的一晚：高樓夜景餐廳，再到飯店酒吧小酌。',tip:'有主見很好，但要確定他也尊重你的意見和界線。'}};
var K='ABCD',i=0,sc,best,$=function(id){return document.getElementById(id)};
function show(id){['intro','quiz','result'].forEach(function(s){$(s).hidden=s!==id});window.scrollTo(0,0)}
function ask(){var q=Q[i];$('qn').textContent='第 '+(i+1)+' 題';$('prog').style.width=(i/Q.length*100)+'%';$('qt').textContent=q[0];
 var o=$('opts');o.innerHTML='';q[1].forEach(function(t,k){var b=document.createElement('button');b.className='opt';b.textContent=t;b.onclick=function(){sc[K[k]]++;i++;i<Q.length?ask():done()};o.appendChild(b)});o.firstChild.focus()}
function done(){best='A';K.split('').forEach(function(k){if(sc[k]>sc[best])best=k});var r=R[best];
 try{localStorage.setItem('yy_match',best)}catch(e){}
 $('rw').textContent=r.w;$('rp').textContent=r.p;$('rd').textContent=r.d;$('rl').textContent=r.l;$('rdate').textContent=r.date;$('rtip').textContent=r.tip;
 var url='https://onethirdsugar.com/quiz/match/',txt='我最適合「'+r.w+'」：'+r.d+' 你適合大叔還是小狼狗？';
 $('line').href='https://social-plugins.line.me/lineit/share?url='+encodeURIComponent(url)+'&text='+encodeURIComponent(txt);
 $('threads').href='https://www.threads.net/intent/post?text='+encodeURIComponent(txt+' '+url);
 show('result')}
function wrap(ctx,text,x,y,maxW,lh){var line='',lines=[];for(var c of text){if(ctx.measureText(line+c).width>maxW){lines.push(line);line=c}else line+=c}lines.push(line);lines.forEach(function(l,n){ctx.fillText(l,x,y+n*lh)});return y+lines.length*lh}
function card(){var r=R[best],c=document.createElement('canvas');c.width=1080;c.height=1920;var x=c.getContext('2d');
 x.fillStyle='#F4EFE5';x.fillRect(0,0,1080,1920);x.fillStyle='#FCFAF4';x.fillRect(70,150,940,1560);x.strokeStyle='#D9CFB8';x.lineWidth=6;x.strokeRect(70,150,940,1560);
 var serif='"Noto Serif TC", "PingFang TC", serif';x.textAlign='center';
 x.fillStyle='#6B5D45';x.font='500 40px '+serif;x.fillText('你適合大叔，還是小狼狗？',540,290);
 x.fillStyle='#D9CFB8';x.fillRect(170,340,740,4);
 x.fillStyle='#6B5D45';x.font='400 44px '+serif;x.fillText('最適合我的是',540,470);
 x.fillStyle='#1d1a17';x.font='900 150px '+serif;x.fillText(r.w,540,660);
 x.fillStyle='#6B5D45';x.font='400 40px '+serif;x.fillText(r.p,540,740);
 x.fillStyle='#A63F58';x.font='900 52px '+serif;var y=wrap(x,r.d,540,880,780,72);
 x.fillStyle='#4a443d';x.font='400 38px "PingFang TC","Noto Sans TC",sans-serif';x.textAlign='left';
 x.fillStyle='#6B5D45';x.font='500 32px "PingFang TC",sans-serif';x.fillText('理想約會',170,y+70);
 x.fillStyle='#1d1a17';x.font='400 40px "PingFang TC","Noto Sans TC",sans-serif';y=wrap(x,r.date,170,y+130,740,60);
 x.fillStyle='#6B5D45';x.font='500 32px "PingFang TC",sans-serif';x.fillText('戀愛小提醒',170,y+50);
 x.fillStyle='#1d1a17';x.font='400 40px "PingFang TC","Noto Sans TC",sans-serif';y=wrap(x,r.tip,170,y+110,740,60);
 x.textAlign='center';x.fillStyle='#A63F58';x.font='500 40px '+serif;x.fillText('你適合哪一型？1 分鐘測測看',540,Math.max(y+120,1600));
 x.textAlign='center';x.fillStyle='#1d1a17';x.font='900 46px '+serif;x.fillText('微糖 1/3 Sugar',540,1810);
 x.fillStyle='#6B5D45';x.font='400 32px "PingFang TC",sans-serif';x.fillText('onethirdsugar.com/quiz/match',540,1866);
 return c}
function saveImg(){var go=function(){var c=card();c.toBlob(function(b){var f=new File([b],'微糖測驗結果.png',{type:'image/png'});
  if(navigator.canShare&&navigator.canShare({files:[f]})){navigator.share({files:[f],title:'你適合大叔，還是小狼狗？'}).catch(function(){})}
  else{var a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='微糖測驗結果.png';document.body.appendChild(a);a.click();a.remove();$('img').textContent='已存成圖片，分享到限動吧'}},'image/png')};
 (document.fonts&&document.fonts.ready?document.fonts.ready:Promise.resolve()).then(go)}
$('start').onclick=function(){i=0;sc={A:0,B:0,C:0,D:0};show('quiz');ask()};
$('again').onclick=function(){show('intro')};
$('img').onclick=saveImg;
})();

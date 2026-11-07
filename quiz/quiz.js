// 約會人格測驗：6 題，每個選項對應一型（A 改天約、B 到家說一聲、C 我都可以、D 哈哈哈哈）
(function(){
var Q=[
 ['對方傳來「改天約」，你會？',['好，那就等他','回「那你哪天方便？」','都可以啊，看他','傳一張好笑的貼圖']],
 ['第一次約會，你最想去？',['安靜的咖啡廳','對方想去的地方','都可以，你決定','有得玩的：展覽、夜市']],
 ['約會結束回到家，你會？',['等對方先傳','傳「到家了嗎？」','看今天聊得怎樣','傳一張今天的梗圖']],
 ['聊天時你最常打的是？','嗯嗯、好、OK|你吃飯了嗎？|都可以|哈哈哈哈哈哈'.split('|')],
 ['對方遲到 15 分鐘，你會？',['默默記一筆','問他還好嗎、路上小心','沒差，我也剛到','先自拍等他']],
 ['你理想的見面頻率是？',['一兩週一次，慢慢來','每週固定見一次','看對方，配合就好','想到就約']]];
var R={
 A:{w:'改天約',p:'gǎi tiān yuē',d:'不是不想，是想先確定。',l:'慢熟、謹慎，喜歡先觀察再靠近。你不輕易答應，但答應了就會準時出現。',date:'白天的咖啡廳，一小時就好，聊不來也不尷尬。',m:'到家說一聲型：他的耐心剛好等得到你。'},
 B:{w:'到家說一聲',p:'dào jiā shuō yì shēng',d:'我有點在乎你了。',l:'體貼、細心，會記得對方說過的小事。你的關心很具體，對方很容易感覺到被放在心上。',date:'對方提過想去的那間店，你默默記下來了。',m:'改天約型：你的穩定讓他敢慢慢打開。'},
 C:{w:'我都可以',p:'wǒ dōu kě yǐ',d:'我有意見，但想先聽你的。',l:'隨和好相處，很會配合對方，只是有時候忘了說出自己想要的。',date:'讓對方選地點，你負責選甜點——偶爾也說說你想要什麼。',m:'哈哈哈哈型：他會把你的想法逗出來。'},
 D:{w:'哈哈哈哈',p:'hā hā hā hā',d:'四個哈以上，是真的覺得你好笑。',l:'氣氛製造機，跟你約會不會冷場。你用好笑表達好感，認真的話常藏在玩笑後面。',date:'展覽、夜市或桌遊店，有東西可以一起吐槽。',m:'我都可以型：他接得住你所有的梗。'}};
var K='ABCD',i=0,sc={A:0,B:0,C:0,D:0},$=function(id){return document.getElementById(id)};
function show(id){['intro','quiz','result'].forEach(function(s){$(s).hidden=s!==id});window.scrollTo(0,0)}
function ask(){var q=Q[i];$('qn').textContent='第 '+(i+1)+' 題';$('prog').style.width=(i/Q.length*100)+'%';$('qt').textContent=q[0];
 var o=$('opts');o.innerHTML='';q[1].forEach(function(t,k){var b=document.createElement('button');b.className='opt';b.textContent=t;b.onclick=function(){sc[K[k]]++;i++;i<Q.length?ask():done()};o.appendChild(b)});o.firstChild.focus()}
function done(){var best='A';K.split('').forEach(function(k){if(sc[k]>sc[best])best=k});var r=R[best];
 $('rw').textContent=r.w;$('rp').textContent=r.p;$('rd').textContent=r.d;$('rl').textContent=r.l;$('rdate').textContent=r.date;$('rmatch').textContent=r.m;
 var url='https://onethirdsugar.com/quiz/',txt='我的約會暗號是「'+r.w+'」：'+r.d+' 你是哪一句？';
 $('line').href='https://social-plugins.line.me/lineit/share?url='+encodeURIComponent(url)+'&text='+encodeURIComponent(txt);
 $('threads').href='https://www.threads.net/intent/post?text='+encodeURIComponent(txt+' '+url);
 $('copy').onclick=function(){var s=txt+' '+url;(navigator.clipboard?navigator.clipboard.writeText(s):Promise.reject()).then(function(){$('copy').textContent='已複製，貼給朋友吧'},function(){prompt('複製這段文字：',s)})};
 show('result')}
$('start').onclick=function(){i=0;sc={A:0,B:0,C:0,D:0};show('quiz');ask()};
$('again').onclick=function(){show('intro')};
})();

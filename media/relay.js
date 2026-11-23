fetch('reel-sd.mp4').then(r=>r.arrayBuffer()).then(b=>parent.postMessage({kind:'vid',buf:b},'*'));

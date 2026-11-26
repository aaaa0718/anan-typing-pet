from pathlib import Path
import subprocess
import shutil

source = Path(__file__).resolve().parent
app = source.parent / 'dist' / '安安打字操作.app'
resources = app / 'Contents/Resources'
binary = app / 'Contents/MacOS/TypingGirl'
resources.mkdir(parents=True, exist_ok=True)
binary.parent.mkdir(parents=True, exist_ok=True)
html = (source / 'preview.html').read_text()
bridge = '''
 let secureInput=false;
 window.desktopPet={
  key(code){if(secureInput)return;const k=keys.find(k=>k.code===code);if(k)press(code,k.label||'空格');},
  outfit(id){return selectOutfit(id,false);},
  pointer(x,y,dx,dy){if(dx||dy)wakePet();setHeadHover(isOverHead(x,y));if(!headHovered)moveMouse(dx,dy);},
  secure(enabled){secureInput=enabled;if(enabled){if(typeof resetRig==='function')resetRig();pops=[];active.clear();lastPress=-10000;recent=[];schedule();}},
  demo(kind){if(kind==='rest')root.querySelector('#tg-rest-demo').click();else if(kind==='angry')angryDemo.click();else if(kind==='mouse')mouseDemo.click();else play();},
  stop(){demoTimers.forEach(clearTimeout);demoTimers=[];if(typeof resetRig==='function')resetRig();setHeadHover(false);pops=[];active.clear();lastPress=-10000;schedule();}
 };
'''
anchor=' sheet.onload=()=>{ready=true;schedule();};'
assert html.count(anchor)==1
html=html.replace(anchor,bridge+anchor)
style='''<style>
html,body{margin:0;padding:0;background:transparent!important;overflow:hidden;width:100%;height:100%}
#typing-girl-preview{background:transparent!important;padding:0;width:100%;height:100%}
#typing-girl-preview .tg-stage{width:100%;max-width:none;height:100%;margin:0;aspect-ratio:auto}
#typing-girl-preview .tg-controls,#typing-girl-preview #tg-state,#typing-girl-preview .tg-mouse-zone{display:none!important}
</style>'''
page='<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src data:; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'; connect-src \'none\';"></head><body>'+html+style+'</body></html>'
(resources/'pet.html').write_text(page)
shutil.copy2(source/'Info.plist',app/'Contents/Info.plist')
subprocess.run(['swiftc','-module-cache-path',str(source.parent/'dist/.module-cache'),'-target','arm64-apple-macosx13.0','-O','-framework','Cocoa','-framework','WebKit','-framework','Carbon',str(source/'main.swift'),'-o',str(binary)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(app)

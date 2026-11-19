"""One recording-clone workflow. No text-description controls or hidden voice edits."""
import asyncio
from pathlib import Path
import tkinter as tk
from tkinter import filedialog,ttk
import uuid

from voice_client import VoiceError

STATES={'processing':'处理中','running':'处理中','unknown':'待核实','ready':'可用',
        'complete':'已完成','failed':'失败','cancelled':'已取消'}


class VoicePanel:
    def __init__(self,parent,worker,role,device,on_close):
        self.worker,self.api=worker,worker.voice
        self.role,self.device,self.on_close=role,device,on_close
        self.root=tk.Toplevel(parent)
        self.root.title('自定义声音 · 录音复刻')
        x=max(0,min(parent.winfo_rootx()+30,parent.winfo_screenwidth()-900))
        y=max(0,min(parent.winfo_rooty()+20,parent.winfo_screenheight()-810))
        self.root.geometry(f'900x760+{x}+{y}')
        self.root.minsize(820,720)
        self.root.transient(parent)
        self.root.grab_set()
        self.root.protocol('WM_DELETE_WINDOW',self.close)
        self.path=None;self.items=[];self.binding={'revision':0};self.job=None
        self.busy=False;self.closing=False;self.poll_id=None
        self.futures=set()
        outer=ttk.Frame(self.root,padding=18);outer.pack(fill='both',expand=True)
        footer=ttk.Frame(outer);footer.pack(side='bottom',fill='x')
        self.status=tk.StringVar(value='选择录音并听原音，或从列表选择已有声音。')
        ttk.Label(footer,textvariable=self.status,wraplength=830).pack(fill='x',pady=(10,4))
        ttk.Label(footer,text='创建成功后保存到列表，点击“应用”才替换角色声音。关闭窗口不自动重播。',foreground='#6a7084').pack(anchor='w')
        ttk.Label(outer,text='给'+('小星' if role=='xing' else '小月')+'选择声音',font=('Microsoft YaHei UI',18,'bold')).pack(anchor='w')
        self.binding_text=tk.StringVar(value='正在读取当前声音…')
        ttk.Label(outer,textvariable=self.binding_text).pack(anchor='w',pady=(4,12))
        box=ttk.LabelFrame(outer,text='1  上传已有录音',padding=12);box.pack(fill='x')
        line=ttk.Frame(box);line.pack(fill='x')
        self.choose=ttk.Button(line,text='选择录音',command=self.select_file);self.choose.pack(side='left')
        self.file_text=tk.StringVar(value='WAV / MP3 / M4A · 10–30 秒 · ≤10 MB')
        ttk.Label(line,textvariable=self.file_text,wraplength=560).pack(side='left',padx=12)
        self.original=ttk.Button(line,text='听原录音',command=self.play_original);self.original.pack(side='right')
        line=ttk.Frame(box);line.pack(fill='x',pady=8)
        ttk.Label(line,text='声音名称').pack(side='left')
        self.name=ttk.Entry(line,width=30);self.name.pack(side='left',padx=10)
        self.consent=tk.BooleanVar(value=False)
        ttk.Checkbutton(box,text='我确认可以使用这段录音，并同意将其提交给声音服务进行复刻。',variable=self.consent).pack(anchor='w')
        self.create_button=ttk.Button(box,text='开始复刻并保存',command=self.create);self.create_button.pack(anchor='w',pady=(8,0))
        box=ttk.LabelFrame(outer,text='2  已保存的声音',padding=12);box.pack(fill='both',expand=True,pady=12)
        self.list=ttk.Treeview(box,columns=('name','status','duration'),show='headings',height=3,selectmode='browse')
        for key,label,width in [('name','名称',330),('status','状态',120),('duration','参考时长',100)]:
            self.list.heading(key,text=label);self.list.column(key,width=width)
        self.list.pack(fill='both',expand=True)
        self.list.bind('<<TreeviewSelect>>',self.selected)
        line=ttk.Frame(box);line.pack(fill='x',pady=(8,0))
        self.refresh_button=ttk.Button(line,text='刷新列表 / 状态',command=self.refresh);self.refresh_button.pack(side='left')
        self.apply_button=ttk.Button(line,text='应用到当前角色',command=self.apply);self.apply_button.pack(side='left',padx=8)
        self.default_button=ttk.Button(line,text='恢复默认声音',command=self.default);self.default_button.pack(side='left')
        box=ttk.LabelFrame(outer,text='3  用新台词试听',padding=12);box.pack(fill='x')
        self.text=tk.Text(box,height=2,wrap='word',font=('Microsoft YaHei UI',10))
        self.text.insert('1.0','你好，今天我们可以一起聊聊最近发生的事情。你可以慢慢说，我会认真听。')
        self.text.pack(fill='x')
        line=ttk.Frame(box);line.pack(fill='x',pady=(8,0))
        self.generate=ttk.Button(line,text='生成试听',command=self.preview);self.generate.pack(side='left')
        self.listen=ttk.Button(line,text='播放试听',command=self.play_preview);self.listen.pack(side='left',padx=8)
        self.stop_button=ttk.Button(line,text='停止播放',command=lambda:self.launch(self.api.stop(),lambda _:self.status.set('播放已停止。'),lock=False));self.stop_button.pack(side='left')
        self.retry_button=ttk.Button(line,text='重试失败任务',command=self.retry);self.retry_button.pack(side='left',padx=8)
        self.cancel_button=ttk.Button(line,text='取消当前任务',command=self.cancel);self.cancel_button.pack(side='left')
        self.controls();self.refresh()

    def launch(self,coro,callback=None,lock=True):
        if self.closing:coro.close();return
        if lock and self.busy:coro.close();return
        if lock:self.busy=True;self.controls()
        future=asyncio.run_coroutine_threadsafe(coro,self.worker.loop)
        self.futures.add(future)
        def wait():
            if self.closing:return
            if not future.done():self.root.after(80,wait);return
            self.futures.discard(future)
            if lock:self.busy=False
            try:
                value=future.result()
                if callback:callback(value)
            except Exception as exc:
                self.status.set(str(exc) if isinstance(exc,VoiceError) else '本地操作失败，请检查录音、设备或网关后重试。')
            self.controls()
        self.root.after(80,wait)

    def current(self):
        selected=self.list.selection()
        return next((x for x in self.items if selected and x['id']==selected[0]),None)

    def controls(self):
        active=self.job and self.job['status'] in ('running','unknown')
        row=self.current()
        ready=row and row['status']=='ready'
        for button in (self.choose,self.create_button,self.refresh_button,self.apply_button,self.default_button,self.generate,self.original,self.listen,self.retry_button):
            button.configure(state='disabled' if self.busy else 'normal')
        if not self.path:self.original.configure(state='disabled')
        if not ready:
            self.apply_button.configure(state='disabled');self.generate.configure(state='disabled')
        if active:self.create_button.configure(state='disabled');self.generate.configure(state='disabled')
        if not self.job or not self.job.get('audio_url'):self.listen.configure(state='disabled')
        if not self.job or self.job['status'] not in ('failed','cancelled'):self.retry_button.configure(state='disabled')
        self.cancel_button.configure(state='normal' if active and not self.busy else 'disabled')

    def select_file(self):
        path=filedialog.askopenfilename(parent=self.root,title='选择参考录音',filetypes=[('录音','*.wav *.mp3 *.m4a')])
        if not path:return
        self.path=Path(path);self.file_text.set(self.path.name);self.consent.set(False)
        self.name.delete(0,'end');self.name.insert(0,'我的声音')
        self.controls()

    def play_original(self):
        if self.path:
            self.status.set('正在播放原录音…')
            self.launch(self.api.play(self.device,path=self.path),lambda _:self.status.set('原录音试听结束。'))

    def create(self):
        name=self.name.get().strip()
        if not self.path or not 1<=len(name)<=40 or not self.consent.get():
            self.status.set('请选择录音、填写 1–40 字名称，并勾选提交确认。');return
        self.status.set('正在上传和检查录音…')
        self.launch(self.api.upload(self.path,name,uuid.uuid4().hex),self.accept_job)

    def accept_job(self,job):
        self.job=job
        self.show_job()
        self.refresh(prefer=job['profile_id'])

    def show_job(self):
        job=self.job
        if not job:return
        message=('复刻' if job['kind']=='clone' else '试听')+'任务：'+STATES.get(job['status'],job['status'])
        if job.get('code'):message+='。'+str(VoiceError(job['code']))
        if job['status']=='cancelled' and job['kind']=='clone':message='已取消等待；云端仍可能完成，稍后刷新列表核实，不会自动应用。'
        self.status.set(message)
        if self.poll_id:self.root.after_cancel(self.poll_id);self.poll_id=None
        if job['status'] in ('running','unknown'):
            self.poll_id=self.root.after(1500,self.poll_job)
        self.controls()

    def poll_job(self):
        self.poll_id=None
        if self.closing or not self.job:return
        if self.busy:self.poll_id=self.root.after(1500,self.poll_job);return
        jid=self.job['id']
        def done(value):
            if self.job and self.job['id']==jid:
                self.job=value;self.show_job()
                if value['status'] in ('complete','failed','cancelled'):self.refresh(prefer=value['profile_id'])
        self.launch(self.api.job(jid),done)

    def refresh(self,prefer=None):
        current=self.current()
        wanted=prefer or (current['id'] if current else None)
        def done(value):
            self.items,self.binding=value
            self.binding_text.set('当前角色声音：'+self.binding['name'])
            for item in self.list.get_children():self.list.delete(item)
            for row in self.items:
                self.list.insert('', 'end',iid=row['id'],values=(row['name'],STATES.get(row['status'],row['status']),str(row['audio']['duration_seconds'])+' 秒'))
            wanted_id=wanted or self.binding['profile_id'] or (self.items[0]['id'] if self.items else None)
            if wanted_id and self.list.exists(wanted_id):self.list.selection_set(wanted_id)
        self.launch(self.api.catalog(self.role),done)

    def selected(self,event=None):
        if self.busy or self.closing:return
        row=self.current()
        if row and row.get('last_job_id'):
            jid=row['last_job_id']
            def done(job):
                selected=self.current()
                if selected and selected['id']==row['id']:
                    self.job=job
                    if job['kind']=='preview' and 'text' in job:
                        self.text.delete('1.0','end');self.text.insert('1.0',job['text'])
                    self.show_job()
            self.launch(self.api.job(jid),done)

    def preview(self):
        row=self.current();text=self.text.get('1.0','end-1c').strip()
        if row and 1<=len(text)<=200:
            self.status.set('正在生成试听，不调用 DeepSeek…')
            self.launch(self.api.preview(row['id'],text,uuid.uuid4().hex),self.accept_job)
        else:self.status.set('请选择可用音色，试听台词为 1–200 字。')

    def play_preview(self):
        if self.job and self.job.get('audio_url'):
            self.status.set('正在播放生成的试听…')
            self.launch(self.api.play(self.device,jid=self.job['id']),lambda _:self.status.set('试听播放结束。'))

    def apply(self):
        row=self.current()
        if row:self.launch(self.api.bind(self.role,row['id'],self.binding['revision']),self.bound)

    def default(self):self.launch(self.api.bind(self.role,None,self.binding['revision']),self.bound)
    def bound(self,binding):
        self.binding=binding;self.binding_text.set('当前角色声音：'+binding['name'])
        self.status.set('已保存。下一次聊天朗读使用：'+binding['name'])

    def retry(self):
        if self.job:self.launch(self.api.retry(self.job['id'],uuid.uuid4().hex),self.accept_job)

    def cancel(self):
        if self.job:self.launch(self.api.cancel(self.job['id']),self.accept_job)

    def close(self):
        if self.closing:return
        self.closing=True
        if self.poll_id:self.root.after_cancel(self.poll_id)
        for f in self.futures:f.cancel()
        async def stop():
            await self.api.stop()
            if self.job and self.job['kind']=='preview' and self.job['status'] in ('running','unknown'):
                try:await self.api.cancel(self.job['id'])
                except Exception:pass
        future=asyncio.run_coroutine_threadsafe(stop(),self.worker.loop)
        def finish():
            if not future.done():self.root.after(80,finish);return
            self.root.grab_release();self.root.destroy();self.on_close()
        finish()

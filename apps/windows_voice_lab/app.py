"""Windows desktop test window; no supplier credentials, microphone or phone dependency."""
import argparse
import asyncio
import json
import queue
import threading
import time
from datetime import datetime
from pathlib import Path
import tkinter as tk
from tkinter import ttk

from client import Client, load_config
from player import default_output, output_devices
from voice_client import VoiceClient
from voice_panel import VoicePanel

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / '.model-local' / 'windows-voice-lab'


class Worker:
    def __init__(self, config, data):
        self.events = queue.Queue(maxsize=32)
        self.loop = asyncio.new_event_loop()
        url, token = load_config(config)
        self.client = Client(url, token, data, notify=self.post)
        self.voice = VoiceClient(url,token)
        self.thread = threading.Thread(target=self.loop.run_forever, daemon=True)
        self.thread.start()
        self.submit(self.client.health())

    def post(self, event):
        if self.events.full():
            try:
                self.events.get_nowait()
            except queue.Empty:
                pass
        self.events.put_nowait(event)

    def submit(self, coroutine):
        future = asyncio.run_coroutine_threadsafe(coroutine, self.loop)
        def finished(done):
            try:
                done.result()
            except Exception:
                self.post({'fatal': '本地操作未完成，请检查网关或磁盘后重试。'})
        future.add_done_callback(finished)
        return future

    async def close(self):
        await self.voice.close()
        await self.client.close()


class Window:
    def __init__(self, root, worker):
        self.root, self.worker = root, worker
        self.state = None
        self.closing = False
        self.voice_panel = None
        self.rendered = None
        root.title('星语 · Windows 流式声音测试')
        root.geometry('1080x780')
        root.minsize(940, 740)
        root.configure(bg='#f3f4fa')
        root.option_add('*Font', ('Microsoft YaHei UI', 10))
        style = ttk.Style()
        style.theme_use('clam')
        style.configure('TFrame', background='#f3f4fa')
        style.configure('TLabel', background='#f3f4fa', foreground='#26314b')
        style.configure('TButton', padding=(14, 9), font=('Microsoft YaHei UI', 10))
        style.configure('Accent.TButton', background='#6454c9', foreground='white')
        style.map('Accent.TButton', background=[('active', '#7766de'), ('disabled', '#d2cee9')])
        outer = ttk.Frame(root, padding=16)
        outer.pack(fill='both', expand=True)
        header = ttk.Frame(outer)
        header.pack(fill='x')
        ttk.Label(header, text='星语  /  声音测试台', font=('Microsoft YaHei UI', 18, 'bold')).pack(side='left')
        self.mode = ttk.Label(header, text='正在连接', foreground='#6454c9')
        self.mode.pack(side='right', padx=8)
        ttk.Label(outer, text='Windows 先验证  ·  完整回复后自动朗读  ·  不使用麦克风', foreground='#69738b').pack(anchor='w', pady=(3, 10))

        toolbar = ttk.Frame(outer)
        toolbar.pack(fill='x', pady=(0, 10))
        ttk.Label(toolbar, text='当前角色').pack(side='left')
        self.role = ttk.Combobox(toolbar, values=['小星', '小月'], width=8, state='readonly')
        self.role.current(0)
        self.role.pack(side='left', padx=(8, 22))
        self.role.bind('<<ComboboxSelected>>', self.select_role)
        ttk.Label(toolbar, text='播放设备').pack(side='left')
        try:
            self.devices = output_devices()
            chosen = default_output(self.devices)
        except Exception:
            self.devices, chosen = [], None
        self.device = ttk.Combobox(toolbar, values=[d[1] for d in self.devices], state='readonly', width=42)
        self.device.pack(side='left', padx=8, fill='x', expand=True)
        if self.devices:
            self.device.current(next((i for i, d in enumerate(self.devices) if d[0] == chosen), 0))
        self.check = ttk.Button(toolbar, text='检查连接', command=lambda: self.worker.submit(self.worker.client.health()))
        self.check.pack(side='right', padx=(10, 0))
        self.voices_button=ttk.Button(toolbar,text='自定义声音',command=self.open_voices)
        self.voices_button.pack(side='right',padx=(8,0))

        footer = ttk.Frame(outer)
        footer.pack(side='bottom', fill='x')
        body = ttk.Frame(outer)
        body.pack(fill='both', expand=True)
        body.columnconfigure(0, weight=1)
        body.rowconfigure(0, weight=1)
        conversation = tk.Frame(body, bg='white', highlightbackground='#dde1ec', highlightthickness=1)
        conversation.grid(row=0, column=0, sticky='nsew', padx=(0, 18))
        tk.Label(conversation, text='聊天记录 · 最近 40 轮', bg='white', fg='#26314b', font=('Microsoft YaHei UI', 12, 'bold'), anchor='w').pack(fill='x', padx=18, pady=(10, 4))
        scroll = ttk.Scrollbar(conversation)
        scroll.pack(side='right', fill='y')
        self.history = tk.Text(conversation, wrap='word', bg='white', fg='#26314b', relief='flat',
                               padx=18, pady=10, spacing3=9, width=48, height=12, state='disabled',
                               yscrollcommand=scroll.set)
        self.history.pack(fill='both', expand=True)
        scroll.configure(command=self.history.yview)
        self.history.tag_configure('user', foreground='#6454c9', font=('Microsoft YaHei UI', 10, 'bold'))
        self.history.tag_configure('role', foreground='#257c72', font=('Microsoft YaHei UI', 10, 'bold'))
        self.history.tag_configure('muted', foreground='#8991a3')

        metrics = tk.Frame(body, bg='#ebe9f7', width=282, padx=16, pady=12)
        metrics.grid(row=0, column=1, sticky='ns')
        metrics.grid_propagate(False)
        tk.Label(metrics, text='这一次有多快', bg='#ebe9f7', fg='#3d356c', font=('Microsoft YaHei UI', 13, 'bold')).pack(anchor='w')
        self.values = {}
        for key, label in [('output_ms', '本次操作 → 首次出声'), ('text_ms', '发送 → 完整文字'),
                           ('text_to_output_ms', '完整文字 → 首次出声')]:
            tk.Label(metrics, text=label, bg='#ebe9f7', fg='#696080').pack(anchor='w', pady=(9, 0))
            value = tk.StringVar(value='—')
            tk.Label(metrics, textvariable=value, bg='#ebe9f7', fg='#443879', font=('Segoe UI', 18, 'bold')).pack(anchor='w')
            self.values[key] = value
        self.details = tk.StringVar(value='连接复用：—\n缓冲不足：—')
        tk.Label(metrics, textvariable=self.details, justify='left', anchor='w', bg='#ebe9f7', fg='#5d5674', wraplength=240).pack(fill='x', pady=(10, 6))
        tk.Label(metrics, text='出声时间为设备输出时钟估算，\n不含远程桌面到耳机的传输。', justify='left', bg='#ebe9f7', fg='#79718e', font=('Microsoft YaHei UI', 9)).pack(anchor='w', pady=(0, 8))
        self.export = ttk.Button(metrics, text='保存本次指标', command=self.export_metrics)
        self.export.pack(anchor='w')

        self.status = tk.StringVar(value='正在连接服务器…')
        ttk.Label(footer, textvariable=self.status, wraplength=1080, foreground='#4c5975').pack(fill='x', pady=(10, 6))
        self.input = tk.Text(footer, height=2, wrap='word', relief='solid', bd=1, bg='white', fg='#26314b', padx=12, pady=6)
        self.input.pack(fill='x')
        self.input.bind('<Control-Return>', lambda event: self.send() or 'break')
        buttons = ttk.Frame(footer)
        buttons.pack(fill='x', pady=(10, 0))
        self.send_button = ttk.Button(buttons, text='发送并朗读', style='Accent.TButton', command=self.send)
        self.send_button.pack(side='left')
        self.stop_button = ttk.Button(buttons, text='停止', command=lambda: self.worker.submit(self.worker.client.stop()))
        self.stop_button.pack(side='left', padx=8)
        self.retry_voice = ttk.Button(buttons, text='重试朗读', command=lambda: self.send(voice_retry=True))
        self.retry_voice.pack(side='left')
        self.retry_text = ttk.Button(buttons, text='重试回复', command=lambda: self.send(text_retry=True))
        self.retry_text.pack(side='left', padx=8)
        ttk.Label(buttons, text='Ctrl+Enter 发送 · Enter 换行').pack(side='right')
        ttk.Label(footer, text='记录仅保存在此电脑的测试库。重试朗读只调用声音服务；重试回复会重新请求主模型。', foreground='#7c8496', font=('Microsoft YaHei UI', 9)).pack(anchor='w', pady=(6, 0))
        self.set_buttons(False, None)
        self.input.focus_set()
        root.protocol('WM_DELETE_WINDOW', self.close)
        root.after(80, self.poll)

    def set_buttons(self, busy, last):
        self.send_button.configure(state='disabled' if busy else 'normal')
        self.stop_button.configure(state='normal' if busy else 'disabled')
        self.role.configure(state='disabled' if busy else 'readonly')
        self.device.configure(state='disabled' if busy else 'readonly')
        self.check.configure(state='disabled' if busy else 'normal')
        self.voices_button.configure(state='disabled' if busy else 'normal')
        self.retry_voice.configure(state='normal' if not busy and last and last['text_state'] == 'complete' else 'disabled')
        self.retry_text.configure(state='normal' if not busy and last and last['text_state'] != 'complete' else 'disabled')
        self.export.configure(state='normal' if not busy and self.state and self.state['metrics'] else 'disabled')

    def select_role(self, event=None):
        self.worker.submit(self.worker.client.select('xing' if self.role.current() == 0 else 'yue'))

    def open_voices(self):
        if not self.state or self.state['busy'] or self.voice_panel:return
        if not self.devices:
            self.status.set('请连接播放设备后重新打开窗口。');return
        def closed():self.voice_panel=None
        self.voice_panel=VoicePanel(self.root,self.worker,self.state['role'],self.devices[self.device.current()][0],closed)

    def send(self, voice_retry=False, text_retry=False):
        if str(self.send_button['state']) == 'disabled':
            return
        prompt = self.input.get('1.0', 'end-1c').strip()
        if not voice_retry and not text_retry and not 1 <= len(prompt) <= 2000:
            self.status.set('请输入 1–2000 个字。')
            return
        if not self.devices:
            self.status.set('没有可用的播放设备，请连接耳机或扬声器后重新打开窗口。')
            return
        self.set_buttons(True, None)
        self.worker.submit(self.worker.client.run(prompt, voice_retry=voice_retry, text_retry=text_retry,
                           device=self.devices[self.device.current()][0], started=time.perf_counter()))
        # Keep the draft until storage confirms it, so a failed initial save loses nothing.
        self.pending_prompt = prompt if not voice_retry and not text_retry else None

    def draw(self, state):
        self.state = state
        self.status.set(state['status'])
        self.mode.configure(text=state['mode'])
        self.role.current(0 if state['role'] == 'xing' else 1)
        rows = state['rows']
        if (getattr(self, 'pending_prompt', None) and rows and rows[-1]['prompt'] == self.pending_prompt
                and rows[-1]['id'] == state['active_row']):
            if self.input.get('1.0', 'end-1c').strip() == self.pending_prompt:
                self.input.delete('1.0', 'end')
            self.pending_prompt = None
        self.set_buttons(state['busy'], rows[-1] if rows else None)
        for key, value in self.values.items():
            number = state['metrics'].get(key)
            value.set(f'{number/1000:.2f} 秒' if isinstance(number, (int, float)) else '—')
        m = state['metrics']
        reuse = '已复用' if m.get('reused') else '新建连接' if 'reused' in m else '—'
        self.details.set(f"连接复用：{reuse}\n补静音：{m.get('starved_ms', 0):.0f} ms\n设备下溢：{m.get('underflows', 0)} 次")
        rendered = (rows, state['preview'], state['active_row'], state['role'])
        if rendered != self.rendered:
            self.rendered = rendered
            self.history.configure(state='normal')
            self.history.delete('1.0', 'end')
            if not rows:
                self.history.insert('end', '从一句问候开始。\n回复完成后会自动朗读。', 'muted')
            for row in rows:
                self.history.insert('end', '你\n', 'user')
                self.history.insert('end', row['prompt']+'\n\n')
                self.history.insert('end', ('小星' if state['role'] == 'xing' else '小月')+'\n', 'role')
                reply = state['preview'] if row['id'] == state['active_row'] and state['preview'] else row['reply']
                self.history.insert('end', (reply or '等待回复…')+'\n')
                labels = {'cancelled': '已取消', 'failed': '未完成，可重试', 'interrupted': '上次已中断'}
                if row['text_state'] in labels:
                    self.history.insert('end', labels[row['text_state']]+'\n', 'muted')
                self.history.insert('end', '\n')
            self.history.configure(state='disabled')
            self.history.see('end')

    def poll(self):
        latest = None
        while True:
            try:
                latest = self.worker.events.get_nowait()
            except queue.Empty:
                break
        if latest and not self.closing:
            if 'fatal' in latest:
                self.status.set(latest['fatal'])
                self.set_buttons(False, None)
            else:
                self.draw(latest)
        if not self.closing:
            self.root.after(80, self.poll)

    def export_metrics(self):
        if not self.state or not self.state['metrics']:
            return
        LOCAL.mkdir(parents=True, exist_ok=True)
        path = LOCAL / ('metrics-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f')+'.json')
        try:
            path.write_text(json.dumps({'metrics': self.state['metrics'],
                'output_clock': 'PortAudio outputBufferDacTime estimate; not acoustic measurement',
                'human_listening': 'not_recorded'}, ensure_ascii=False, indent=2), encoding='utf-8')
            self.status.set('已保存指标（不含聊天内容）：'+str(path))
        except OSError:
            self.status.set('指标保存失败，请检查磁盘空间。')

    def close(self):
        if self.closing:
            return
        if self.voice_panel:
            self.voice_panel.close()
            self.root.after(100,self.close)
            return
        self.closing = True
        self.status.set('正在停止声音并关闭连接…')
        future = self.worker.submit(self.worker.close())
        def wait():
            if future.done():
                self.worker.loop.call_soon_threadsafe(self.worker.loop.stop)
                self.root.destroy()
            else:
                self.root.after(80, wait)
        wait()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, default=ROOT/'.model-local/mobile-live.json')
    parser.add_argument('--data', type=Path, default=LOCAL/'history.sqlite')
    args = parser.parse_args()
    root = tk.Tk()
    try:
        worker = Worker(args.config, args.data)
        Window(root, worker)
    except Exception:
        root.title('Windows 声音测试 · 配置检查')
        ttk.Label(root, text='无法启动测试界面。请按 README 配置本机网关与播放环境。\n不会显示或要求粘贴供应商密钥。', padding=30).pack()
    root.mainloop()


if __name__ == '__main__':
    main()

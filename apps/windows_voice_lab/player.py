"""Bounded, output-only PortAudio PCM player. Never opens a microphone."""
import threading
import time

import numpy as np
import sounddevice as sd

RATE = 24000
MAX_BYTES = 12 * 1024 * 1024


def output_devices():
    apis = sd.query_hostapis()
    devices = []
    for index, device in enumerate(sd.query_devices()):
        if device['max_output_channels']:
            api = apis[device['hostapi']]['name']
            devices.append((index, f"{device['name']} · {api}", api))
    return devices


def default_output(devices):
    default = sd.default.device[1]
    default_name = sd.query_devices(default)['name'] if default >= 0 else ''
    for index, name, api in devices:
        if 'WASAPI' in api and name.startswith(default_name):
            return index
    return default if default >= 0 else (devices[0][0] if devices else None)


class Player:
    def __init__(self, device=None, buffer_ms=400):
        self.samples = np.zeros(MAX_BYTES // 2, dtype=np.int16)
        self.written = self.read = 0
        self.significant = -1
        self.first_output = None
        self.starved_frames = self.underflows = self.tail_frames = 0
        self.eof = self.running = self.closed = False
        self.finished = threading.Event()
        self.threshold = RATE * buffer_ms // 1000
        extra = None
        info = sd.query_devices(device, 'output')
        if 'WASAPI' in sd.query_hostapis(info['hostapi'])['name']:
            extra = sd.WasapiSettings(auto_convert=True)
        self.stream = sd.OutputStream(device=device, samplerate=RATE, channels=1,
            dtype='int16', blocksize=0, latency=.04, extra_settings=extra,
            callback=self.callback, finished_callback=self.finished.set)
        self.output_latency = self.stream.latency

    def callback(self, out, frames, clock, status):
        out.fill(0)
        if self.closed:
            raise sd.CallbackAbort
        if status.output_underflow:
            self.underflows += 1
        count = min(frames, self.written-self.read)
        if count:
            out[:count, 0] = self.samples[self.read:self.read+count]
            if self.first_output is None and self.read <= self.significant < self.read+count:
                self.first_output = (time.perf_counter() + clock.outputBufferDacTime-clock.currentTime
                                     + (self.significant-self.read)/RATE)
        self.read += count
        if count < frames:
            if self.eof:
                self.tail_frames += frames-count
            else:
                self.starved_frames += frames-count
        if self.eof and self.read == self.written:
            raise sd.CallbackStop

    def feed(self, pcm):
        if self.closed:
            return
        if len(pcm) % 2 or not pcm:
            raise ValueError('INVALID_PCM')
        data = np.frombuffer(pcm, dtype='<i2')
        end = self.written+len(data)
        if end > len(self.samples):
            raise ValueError('AUDIO_TOO_LARGE')
        self.samples[self.written:end] = data
        # Search on the producer thread, avoiding allocation in the audio callback.
        if self.significant < 0:
            audible = np.flatnonzero((data > 200) | (data < -200))
            if audible.size:
                self.significant = self.written+int(audible[0])
        self.written = end
        if end >= self.threshold:
            self.start()

    def start(self):
        if not self.running and self.written and not self.closed:
            self.running = True
            self.stream.start()

    def end(self):
        self.eof = True
        self.start()

    def metrics(self):
        return {'underflows': self.underflows, 'starved_ms': self.starved_frames/RATE*1000,
                'tail_padding_ms': self.tail_frames/RATE*1000,
                'device_buffer_ms': self.output_latency*1000, 'frames': self.written}

    def close(self):
        if not self.closed:
            self.closed = True
            try:
                self.stream.abort()
            finally:
                self.stream.close()

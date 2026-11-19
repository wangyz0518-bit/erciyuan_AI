"""Run an isolated, TLS-authenticated test gateway on the Mac's private Wi-Fi IP."""
import argparse
import asyncio
import base64
import datetime as dt
import getpass
import ipaddress
import json
import os
from pathlib import Path
import secrets
import socket
import tempfile
import time

import uvicorn
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

from gateway.app import create_app
from gateway.providers import ProviderError, Settings
from gateway.voice_profiles import fingerprint


ROOT = Path(__file__).resolve().parents[2]
NETWORKS = [ipaddress.ip_network(value) for value in
            ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]


def private_ip(value):
    ip = ipaddress.IPv4Address(value)
    if not (ip.is_loopback or any(ip in network for network in NETWORKS)):
        raise ValueError("Use this Mac's private Wi-Fi IPv4 address.")
    return ip


def save(path, content):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as file:
        file.write(content)
        tmp = Path(file.name)
    tmp.replace(path)


def identity(directory, ip):
    """The phone receives the public CA, never either private key."""
    ca_path = directory / 'ca.der'
    cert_path = directory / 'server.pem'
    key_path = directory / 'server-key.pem'
    now = dt.datetime.now(dt.timezone.utc)
    if all(path.is_file() for path in (ca_path, cert_path, key_path)):
        cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
        if cert.not_valid_after_utc > now + dt.timedelta(days=1):
            return ca_path, cert_path, key_path

    def name(value):
        return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, value)])

    def builder(subject, issuer, key):
        return (x509.CertificateBuilder().subject_name(subject).issuer_name(issuer)
                .public_key(key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(now - dt.timedelta(minutes=10))
                .not_valid_after(now + dt.timedelta(days=90)))

    ca_key = ec.generate_private_key(ec.SECP256R1())
    ca_name = name('Companion local test CA')
    ca = (builder(ca_name, ca_name, ca_key)
          .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
          .add_extension(x509.KeyUsage(False, False, False, False, False, True, True, False, False), critical=True)
          .add_extension(x509.SubjectKeyIdentifier.from_public_key(ca_key.public_key()), critical=False)
          .sign(ca_key, hashes.SHA256()))
    key = ec.generate_private_key(ec.SECP256R1())
    cert = (builder(name(str(ip)), ca_name, key)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ip)]), critical=False)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
            .add_extension(x509.KeyUsage(True, False, False, False, False, False, False, False, False), critical=True)
            .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()), critical=False)
            .sign(ca_key, hashes.SHA256()))
    save(key_path, key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                     serialization.NoEncryption()))
    save(cert_path, cert.public_bytes(serialization.Encoding.PEM))
    save(ca_path, ca.public_bytes(serialization.Encoding.DER))
    return ca_path, cert_path, key_path


async def available_voices(service, catalog):
    """Import only provider-confirmed designs into the current test account's catalog."""
    if not catalog.is_file():
        return []
    available = []
    for entry in json.loads(catalog.read_text(encoding='utf-8')):
        voice, name = entry['provider_id'], entry['name']
        try:
            state = await service.enrollment.query(voice)
        except ProviderError:
            continue
        if state != 'OK':
            continue
        digest = fingerprint([service.scope, voice])
        profile_id = digest[:32]
        with service.store.db:
            service.store.db.execute(
                'INSERT OR IGNORE INTO profiles '
                '(id,name,scope,fingerprint,status,provider_id,prefix,reference,metadata,code,created) '
                'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                (profile_id, name, service.scope, digest, 'ready', voice, 'ios'+digest[:16],
                 '', '{}', '', time.time()))
        available.append(voice)
    return available


async def run(args):
    ip = private_ip(args.host)
    directory = ROOT / '.model-local' / 'ios-mac' / str(ip)
    directory.mkdir(parents=True, exist_ok=True)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind((str(ip), args.port))
        ca, cert, key = identity(directory, ip)
        token_file = directory / 'gateway-token'
        if not token_file.exists():
            save(token_file, secrets.token_urlsafe(32).encode())
        settings = Settings.env()
        settings.mode = 'mock' if args.mock else 'live'
        settings.token = token_file.read_text().strip()
        settings.data_dir = str(directory / settings.mode)
        if not args.mock:
            settings.deepseek_key = settings.deepseek_key or getpass.getpass('DeepSeek API key: ').strip()
            settings.dashscope_key = settings.dashscope_key or getpass.getpass('DashScope Beijing API key: ').strip()
            if not settings.deepseek_key or not settings.dashscope_key:
                raise SystemExit('Both server keys are needed for live speech.')
        app = create_app(settings)
        if not args.mock:
            voices = await available_voices(app.state.voice_profiles, ROOT / 'test-voices.json')
            print(f'当前账号可用的随包设计音色：{len(voices)}', flush=True)
            if not settings.voice:
                settings.voice = voices[0] if voices else input('本账号可用的 CosyVoice v3.5 Flash 默认音色 ID：').strip()
            if not settings.voice:
                raise SystemExit('真实语音需要可用的默认音色。')

        config_file = directory.parent / 'iphone.json'
        config = {'MODEL_GATEWAY_PROTOCOL': 'v3', 'MODEL_GATEWAY_URL': f'https://{ip}:{args.port}',
                  'MODEL_GATEWAY_TOKEN': settings.token,
                  'MODEL_GATEWAY_CA_DER': base64.b64encode(ca.read_bytes()).decode()}
        save(config_file, json.dumps(config).encode())
        print(f'配置已写入 {config_file.name}。请保持本终端运行，按 Ctrl+C 结束。', flush=True)
        server = uvicorn.Server(uvicorn.Config(app, ssl_certfile=str(cert), ssl_keyfile=str(key),
                                               access_log=False, log_level='warning'))
        await server.serve(sockets=[listener])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True)
    parser.add_argument('--port', type=int, default=8798)
    parser.add_argument('--mock', action='store_true', help='Local text test without model credentials')
    os.umask(0o077)
    try:
        asyncio.run(run(parser.parse_args()))
    except (ValueError, OSError) as error:
        raise SystemExit(f'网关启动失败：{error}') from None

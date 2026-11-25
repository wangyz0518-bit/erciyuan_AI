"""Android and browser acceptance. Run explicitly with pytest on a booted emulator."""
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import threading
import time

import httpx
from playwright.sync_api import expect, sync_playwright
import pytest
import uvicorn

from gateway.app import create_app
from gateway.providers import Settings


@pytest.fixture
def gateway_port(tmp_path):
    settings = Settings(mode='mock', token=secrets.token_hex(32), data_dir=str(tmp_path),
                        community_enabled=True)
    server = uvicorn.Server(uvicorn.Config(create_app(settings), access_log=False))
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        thread = threading.Thread(target=server.run, kwargs={'sockets': [listener]}, daemon=True)
        thread.start()
        try:
            deadline = time.monotonic() + 20
            while not server.started:
                if not thread.is_alive() or time.monotonic() >= deadline:
                    pytest.fail('The mock community gateway failed to start')
                time.sleep(0.1)
            yield listener.getsockname()[1]
        finally:
            server.should_exit = True
            thread.join(timeout=10)


def review_in_browser(origin, credentials):
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel=os.environ.get('COMMUNITY_BROWSER_CHANNEL'))
        page = browser.new_page()
        page.goto(origin + '/ops/')
        page.get_by_label('用户名').fill(credentials['username'])
        page.get_by_label('密码').fill(credentials['password'])
        page.get_by_role('button', name='登录后台').click()
        expect(page.locator('#pending-reports')).to_have_text('2')
        expect(page.locator('#pending-feedback')).to_have_text('1')
        expect(page.locator('#text-total')).to_have_text('1')
        expect(page.locator('#providers')).to_contain_text('模拟 · ¥0')
        expect(page.locator('#providers')).to_contain_text('deepseek')

        for section, reason, action, reply in (
            ('社区举报', '请审核这条评论', 'hide', '已下架测试评论'),
            ('社区举报', '请审核人设说明', 'hide', '已下架测试分享'),
            ('用户反馈', '建议增加角色标签', 'reply', '已收到角色标签建议'),
        ):
            page.get_by_role('button', name=section, exact=True).click()
            ticket = page.locator('#tickets article').filter(has_text=reason)
            ticket.get_by_role('button').click()
            dialog = page.get_by_role('dialog')
            if action == 'hide':
                dialog.get_by_label('处理方式').select_option(action)
            dialog.get_by_label('给提交人的回复').fill(reply)
            dialog.get_by_role('button', name='确认处理').click()
            expect(dialog).not_to_be_visible()
            page.get_by_label('处理状态').select_option('closed')
            expect(page.locator('#tickets article').filter(has_text=reason)).to_contain_text(reply)
        browser.close()


@pytest.fixture
def android_origin(gateway_port):
    if os.name != 'nt':
        yield f'http://10.0.2.2:{gateway_port}'
        return
    # Windows emulator NAT may route 10.0.2.2 through a host proxy. Forward
    # this run's one loopback port on the explicitly selected test emulator.
    adb = [shutil.which('adb') or 'adb', '-s', os.environ['ANDROID_SERIAL'], 'reverse']
    port = f'tcp:{gateway_port}'
    subprocess.run([*adb, port, port], check=True)
    try:
        yield f'http://127.0.0.1:{gateway_port}'
    finally:
        subprocess.run([*adb, '--remove', port], check=False)


def test_android_and_web_share_one_gateway(gateway_port, android_origin, monkeypatch):
    origin = f'http://127.0.0.1:{gateway_port}'
    credentials = {'username': '验收运营', 'password': secrets.token_hex(16)}
    mobile_dir = Path(__file__).resolve().parents[3] / 'apps' / 'mobile'
    flutter = shutil.which('flutter')
    assert flutter, 'Flutter must be on PATH'
    with httpx.Client(base_url=origin, trust_env=False) as client:
        account = client.post('/community/register', json=credentials).raise_for_status().json()
        monkeypatch.setenv('COMMUNITY_ADMIN_IDS', account['id'])
        client.headers['Authorization'] = 'Bearer ' + account['token']
        command = [
            flutter, 'test', 'integration_test/community_test.dart', '--no-pub',
            '-d', os.environ['ANDROID_SERIAL'], '--reporter', 'expanded',
            f'--dart-define=COMMUNITY_GATEWAY_URL={android_origin}',
            '--dart-define=COMMUNITY_OPERATOR_E2E=true',
        ]
        with subprocess.Popen(command, cwd=mobile_dir) as mobile:
            try:
                deadline = time.monotonic() + 20 * 60
                while True:
                    if mobile.poll() is not None:
                        pytest.fail(f'Android exited before submitting its tickets (exit {mobile.returncode})')
                    counts = client.get('/ops/api/overview').raise_for_status().json()['pending']
                    if counts == {'reports': 2, 'feedback': 1}:
                        break
                    if time.monotonic() >= deadline:
                        pytest.fail(f'Timed out waiting for Android submissions: {counts}')
                    time.sleep(1)
                review_in_browser(origin, credentials)
                assert mobile.wait(timeout=360) == 0, 'Android did not finish operator and account checks'
            finally:
                if mobile.poll() is None:
                    mobile.terminate()

"""Exercise actual asyncio proxy cancellation, without any external network."""
import asyncio

import pytest
from websockets.asyncio.client import connect


@pytest.mark.parametrize('reply', [False, True])
def test_cancel_proxy_handshake_has_no_background_callback_failure(reply):
    async def run():
        reached, finished = asyncio.Event(), asyncio.Event()
        errors=[]
        loop=asyncio.get_running_loop()
        previous=loop.get_exception_handler()
        loop.set_exception_handler(lambda loop,context: errors.append(context))
        async def proxy(reader,writer):
            try:
                await reader.readuntil(b'\r\n\r\n')
                if reply:
                    writer.write(b'HTTP/1.1 200 Connection established\r\n\r\n')
                    await writer.drain()
                reached.set()
                await reader.read()
            except (ConnectionError,asyncio.IncompleteReadError):
                pass
            finally:
                writer.close()
                try: await writer.wait_closed()
                except ConnectionError: pass
                finished.set()
        try:
            async with await asyncio.start_server(proxy,'127.0.0.1',0) as server:
                port=server.sockets[0].getsockname()[1]
                async def opening():
                    async with connect('wss://example.invalid/',proxy=f'http://127.0.0.1:{port}',open_timeout=2):
                        raise AssertionError('Fake proxy must never establish TLS')
                task=asyncio.create_task(opening())
                await asyncio.wait_for(reached.wait(),2)
                task.cancel()
                with pytest.raises(asyncio.CancelledError):await task
                await asyncio.wait_for(finished.wait(),2)
                await asyncio.sleep(.02)
                assert not errors, [(e.get('message'),type(e.get('exception')).__name__) for e in errors]
        finally:
            loop.set_exception_handler(previous)
    asyncio.run(run())

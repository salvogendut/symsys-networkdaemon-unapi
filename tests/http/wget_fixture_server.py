#!/usr/bin/env python3
import argparse
import socket
import socketserver
import time
from pathlib import Path


FIXTURE = Path(__file__).with_name("WGETFIX.TXT").read_bytes()
RESPONSE_PARTS = (
    b"HTTP/1.1 ",
    b"200",
    b" OK\r\nContent-",
    b"Length: ",
    str(len(FIXTURE)).encode("ascii"),
    b"\r\nContent-Type: text/plain\r\n",
    b"Connection: close\r\n",
    b"\r\n",
    FIXTURE[:7],
    FIXTURE[7:],
)


class FixtureHandler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        request = bytearray()
        while b"\r\n\r\n" not in request and len(request) < 4096:
            block = self.request.recv(512)
            if not block:
                break
            request.extend(block)

        first_line = bytes(request).split(b"\r\n", 1)[0]
        print(f"{self.client_address[0]} {first_line.decode('ascii', 'replace')}",
              flush=True)
        for index, part in enumerate(RESPONSE_PARTS):
            self.request.sendall(part)
            if index + 1 < len(RESPONSE_PARTS):
                time.sleep(self.server.fragment_delay)


class FixtureServer(socketserver.TCPServer):
    allow_reuse_address = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--fragment-delay", type=float, default=0.10)
    args = parser.parse_args()

    with FixtureServer((args.bind, args.port), FixtureHandler) as server:
        server.fragment_delay = args.fragment_delay
        print(f"Serving fragmented WGET fixture on {args.bind}:{args.port}",
              flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()

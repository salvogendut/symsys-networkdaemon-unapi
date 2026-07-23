#include <network.h>
#include <stdlib.h>
#include <string.h>
#include <symbos.h>

#define STARTUP_TIMEOUT 1500
#define NETWORK_TIMEOUT 1000
#define RESPONSE_SIZE 1024

static char host[] = "time.akamai.com";
static char request[] =
    "GET / HTTP/1.0\r\n"
    "Host: time.akamai.com\r\n"
    "Connection: close\r\n"
    "\r\n";
static char response[RESPONSE_SIZE];
static char numbuf[8];

extern unsigned short _nettimeout;

static void print_num(int value) {
    itoa(value, numbuf, 10);
    Shell_Print(numbuf);
}

static void print_error(void) {
    Shell_Print("FAIL neterr=");
    print_num((unsigned char)_neterr);
    Shell_Print("\r\n");
}

static void print_ip(char *ip) {
    print_num((unsigned char)ip[0]);
    Shell_Print(".");
    print_num((unsigned char)ip[1]);
    Shell_Print(".");
    print_num((unsigned char)ip[2]);
    Shell_Print(".");
    print_num((unsigned char)ip[3]);
}

static int resolve_when_ready(char *ip) {
    unsigned short started;

    started = Sys_Counter16();
    do {
        if (Net_Init() == 0 && DNS_Resolve(_symbank, host, ip) == 0)
            return 0;
        if (_neterr != ERR_OFFLINE && _neterr != ERR_NOHW)
            return -1;
        Idle();
    } while ((unsigned short)(Sys_Counter16() - started) < STARTUP_TIMEOUT);

    return -1;
}

static int run_transaction(unsigned char pass, char *ip) {
    signed char socket;
    unsigned short received;

    Shell_Print("\r\nPass ");
    print_num(pass);
    Shell_Print("\r\n  TCP open... ");
    socket = TCP_OpenClient(ip, -1, 80);
    if (socket < 0) {
        print_error();
        return -1;
    }
    Shell_Print("OK socket=");
    print_num(socket);
    Shell_Print("\r\n");

    Shell_Print("  Send request... ");
    if (TCP_Send((unsigned char)socket, _symbank, request, strlen(request)) < 0) {
        print_error();
        TCP_Disconnect((unsigned char)socket);
        return -1;
    }
    Shell_Print("OK\r\n");

    Shell_Print("  Receive/close... ");
    memset(response, 0, sizeof(response));
    if (TCP_ReceiveToEnd((unsigned char)socket, _symbank, response,
                         sizeof(response)) < 0) {
        print_error();
        return -1;
    }
    received = (unsigned short)_tcp_progress;
    Shell_Print("OK bytes=");
    print_num(received);
    Shell_Print("\r\n");

    if (received) {
        Shell_Print("  Data: ");
        Shell_Print(response);
        Shell_Print("\r\n");
    }
    return 0;
}

int main(void) {
    char ip[4];
    int first;
    int second;

    Shell_Print("UNAPI network autostart test\r\n");
    _nettimeout = NETWORK_TIMEOUT;
    Shell_Print("Waiting for daemon and DNS... ");
    if (resolve_when_ready(ip) < 0) {
        print_error();
        return 1;
    }
    Shell_Print("OK pid=");
    print_num(_netpid);
    Shell_Print(" ip=");
    print_ip(ip);
    Shell_Print("\r\n");

    first = run_transaction(1, ip);
    second = run_transaction(2, ip);

    Shell_Print("\r\nResult: ");
    if (!first && !second) {
        Shell_Print("PASS - DNS, TCP, RX and socket reuse\r\n");
        return 0;
    }
    Shell_Print("FAIL - see the first failing step above\r\n");
    return 1;
}
